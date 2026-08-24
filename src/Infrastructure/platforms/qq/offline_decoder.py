from __future__ import annotations

import base64
import json
import pathlib
import plistlib
import struct
import urllib.error
import urllib.request
from dataclasses import dataclass

from src.Infrastructure.kugou_decoder import _new_qmc_cipher_from_ekey
from src.Infrastructure.transcoder import detect_audio_container


CHUNK_SIZE = 4 * 1024 * 1024
MUSICEX_MAGIC = b"musicex\x00"


class QQOfflineDecodeError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class QQFooter:
    kind: str
    audio_len: int
    ekey: str | None = None
    song_id: int = 0
    media_mid: str = ""
    filename: str = ""


def _read_utf16le(data: bytes, offset: int, max_len: int) -> str:
    end = min(len(data), offset + max_len)
    raw = data[offset:end]
    stop = next((i for i in range(0, max(0, len(raw) - 1), 2) if raw[i:i + 2] == b"\x00\x00"), len(raw))
    return raw[:stop].decode("utf-16-le", "replace")


def inspect_footer(path: pathlib.Path) -> QQFooter:
    file_size = path.stat().st_size
    if file_size < 8:
        raise QQOfflineDecodeError("qq_invalid_file: 文件过小，无法识别 QQ 音乐加密格式")

    with path.open("rb") as fp:
        fp.seek(-16 if file_size >= 16 else -file_size, 2)
        trailer = fp.read()

        if len(trailer) >= 16 and trailer[-8:] == MUSICEX_MAGIC:
            footer_size, version = struct.unpack("<II", trailer[-16:-8])
            if version != 1 or footer_size < 16 or footer_size > file_size:
                raise QQOfflineDecodeError("qq_invalid_musicex_footer: musicex 尾部结构无效")
            fp.seek(file_size - footer_size)
            metadata = fp.read(footer_size - 16)
            song_id = struct.unpack_from("<I", metadata, 0)[0] if len(metadata) >= 4 else 0
            media_mid = _read_utf16le(metadata, 0x0C, 60)
            filename = _read_utf16le(metadata, 0x48, 68)
            return QQFooter("musicex", file_size - footer_size, song_id=song_id, media_mid=media_mid, filename=filename)

        if trailer[-4:] == b"QTag":
            metadata_size = struct.unpack(">I", trailer[-8:-4])[0]
            if metadata_size <= 0 or metadata_size + 8 > file_size:
                raise QQOfflineDecodeError("qq_invalid_qtag_footer: QTag 尾部结构无效")
            fp.seek(file_size - 8 - metadata_size)
            metadata = fp.read(metadata_size)
            fields = metadata.split(b",", 2)
            if not fields or not fields[0]:
                raise QQOfflineDecodeError("qq_missing_ekey: QTag 中没有内嵌 EKey")
            return QQFooter("qtag", file_size - 8 - metadata_size, fields[0].decode("ascii", "strict"))

        key_size = struct.unpack("<I", trailer[-4:])[0]
        if 0 < key_size <= 0x400 and key_size + 4 < file_size:
            key_start = file_size - 4 - key_size
            fp.seek(key_start)
            raw_ekey = fp.read(key_size)
            return QQFooter("v1", key_start, base64.b64encode(raw_ekey).decode("ascii"))

    raise QQOfflineDecodeError(
        "qq_unknown_footer: 无法识别文件尾部；可能需要从 QQ 音乐客户端导出对应 EKey"
    )


def _resolve_archived_string(objects: list, value: object) -> str | None:
    if isinstance(value, str):
        return value
    if isinstance(value, plistlib.UID):
        index = value.data
        if 0 <= index < len(objects) and isinstance(objects[index], str):
            return objects[index]
    return None


def _mac_qqmusic_credentials() -> tuple[str, str]:
    plist_path = pathlib.Path.home() / "Library/Containers/com.tencent.QQMusicMac/Data/Library/Preferences/com.tencent.QQMusicMac.plist"
    if not plist_path.exists():
        raise QQOfflineDecodeError("qq_credentials_missing: 未找到 macOS QQ 音乐登录信息，请安装并登录 QQ 音乐")
    try:
        root = plistlib.loads(plist_path.read_bytes())
        archived = root.get("AutoLoginUserInfo") if isinstance(root, dict) else None
        archive = plistlib.loads(archived) if isinstance(archived, bytes) else archived
        objects = archive.get("$objects", []) if isinstance(archive, dict) else []
        for item in objects:
            if not isinstance(item, dict) or "strAuthst" not in item:
                continue
            authst = _resolve_archived_string(objects, item.get("strAuthst"))
            uin = _resolve_archived_string(objects, item.get("strUserAccount"))
            if not uin and isinstance(item.get("nCurrUseId"), int):
                uin = str(item["nCurrUseId"])
            if uin and authst:
                return uin, authst
    except PermissionError as exc:
        raise QQOfflineDecodeError(
            "qq_permission_required: macOS 阻止读取 QQ 音乐登录信息；请在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中允许 QKKDecrypt-UI"
        ) from exc
    except QQOfflineDecodeError:
        raise
    except Exception as exc:
        raise QQOfflineDecodeError(f"qq_credentials_invalid: 无法读取 macOS QQ 音乐登录信息：{exc}") from exc
    raise QQOfflineDecodeError("qq_credentials_missing: QQ 音乐尚未登录或登录信息已失效")


def _fetch_musicex_ekey(footer: QQFooter, input_path: pathlib.Path) -> str:
    if not footer.media_mid or not footer.filename:
        raise QQOfflineDecodeError("qq_invalid_musicex_footer: musicex 中缺少歌曲 MID 或文件名")
    uin, authst = _mac_qqmusic_credentials()
    filename = footer.filename
    if pathlib.Path(filename).suffix.lower() not in {".mgg", ".mgg0", ".mgg1", ".mggl", ".mflac", ".mflac0", ".mflach"}:
        filename += input_path.suffix.lower()
    body = {
        "comm": {"authst": authst, "ct": "19", "cv": "1859", "uin": uin, "tmeLoginType": "3"},
        "req_1": {
            "module": "music.vkey.GetEVkey",
            "method": "CgiGetEVkey",
            "param": {
                "filename": [filename], "guid": "10000", "songmid": [footer.media_mid],
                "songtype": [1], "uin": uin, "loginflag": 1, "platform": "20", "ctx": 1,
            },
        },
    }
    request = urllib.request.Request(
        "https://u.y.qq.com/cgi-bin/musicu.fcg",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", "Referer": "https://y.qq.com/"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise QQOfflineDecodeError(f"qq_ekey_network_failed: 获取 EKey 失败：{exc}") from exc
    req_data = payload.get("req_1") or {}
    info_list = ((req_data.get("data") or {}).get("midurlinfo") or [])
    info = info_list[0] if info_list else {}
    result_code = int(info.get("result", -1))
    ekey = str(info.get("ekey") or "")
    if result_code != 0 or not ekey:
        hint = "登录可能已失效或当前账号无该歌曲权限"
        raise QQOfflineDecodeError(f"qq_ekey_unavailable: QQ 音乐未返回 EKey（结果码 {result_code}，{hint}）")
    return ekey


def decode_file(input_path: pathlib.Path, output_path: pathlib.Path, *, fetch_musicex_ekey: bool = True) -> dict:
    footer = inspect_footer(input_path)
    ekey = footer.ekey
    if footer.kind == "musicex":
        if not fetch_musicex_ekey:
            raise QQOfflineDecodeError("qq_musicex_ekey_required: 该文件未内嵌 EKey")
        ekey = _fetch_musicex_ekey(footer, input_path)
    if not ekey:
        raise QQOfflineDecodeError("qq_missing_ekey: 文件中没有可用 EKey")

    try:
        cipher = _new_qmc_cipher_from_ekey(ekey)
    except Exception as exc:
        raise QQOfflineDecodeError(f"qq_ekey_invalid: EKey 解析失败：{exc}") from exc

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_name(f".{output_path.name}.qmc.tmp")
    decoded_bytes = 0
    try:
        with input_path.open("rb") as src, temp_path.open("wb") as dst:
            offset = 0
            remaining = footer.audio_len
            while remaining > 0:
                block = bytearray(src.read(min(CHUNK_SIZE, remaining)))
                if not block:
                    raise QQOfflineDecodeError("qq_truncated_file: 加密音频数据提前结束")
                cipher.decrypt(block, offset)
                dst.write(block)
                offset += len(block)
                remaining -= len(block)
            decoded_bytes = offset
        container, recognition_stage = detect_audio_container(temp_path)
        if container == "bin":
            raise QQOfflineDecodeError("unrecognized_audio_container: QMC2 解密完成但未识别出音频容器")
        if output_path.exists():
            output_path.unlink()
        temp_path.replace(output_path)
        return {
            "output_path": str(output_path),
            "detected_container": container,
            "final_extension": container,
            "recognition_stage": recognition_stage,
            "backend": f"qmc2-offline:{footer.kind}",
            "decoded_bytes": decoded_bytes,
            "footer_kind": footer.kind,
        }
    finally:
        temp_path.unlink(missing_ok=True)
