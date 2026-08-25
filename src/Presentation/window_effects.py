from __future__ import annotations

import ctypes
import platform
from ctypes import wintypes
from typing import Any

from PySide6.QtWidgets import QWidget


class ACCENT_POLICY(ctypes.Structure):
    _fields_ = [
        ("AccentState", ctypes.c_int),
        ("AccentFlags", ctypes.c_int),
        ("GradientColor", ctypes.c_uint32),
        ("AnimationId", ctypes.c_int),
    ]


class WINDOWCOMPOSITIONATTRIBDATA(ctypes.Structure):
    _fields_ = [
        ("Attribute", ctypes.c_int),
        ("Data", ctypes.c_void_p),
        ("SizeOfData", ctypes.c_size_t),
    ]


_ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
_WCA_ACCENT_POLICY = 19


def _rgba_to_abgr(color: tuple[int, int, int, int]) -> int:
    r, g, b, a = color
    return ((a & 0xFF) << 24) | ((b & 0xFF) << 16) | ((g & 0xFF) << 8) | (r & 0xFF)


def apply_win10_acrylic(widget: QWidget, *, dark: bool = True) -> bool:
    if not hasattr(ctypes, "windll"):
        return False
    hwnd = int(widget.winId())
    if hwnd <= 0:
        return False
    try:
        user32 = ctypes.windll.user32
        set_attr = user32.SetWindowCompositionAttribute
    except Exception:
        return False

    tint = (24, 28, 36, 215) if dark else (245, 247, 250, 205)
    accent = ACCENT_POLICY()
    accent.AccentState = _ACCENT_ENABLE_ACRYLICBLURBEHIND
    accent.AccentFlags = 2
    accent.GradientColor = _rgba_to_abgr(tint)
    accent.AnimationId = 0

    data = WINDOWCOMPOSITIONATTRIBDATA()
    data.Attribute = _WCA_ACCENT_POLICY
    data.Data = ctypes.cast(ctypes.pointer(accent), ctypes.c_void_p)
    data.SizeOfData = ctypes.sizeof(accent)
    try:
        return bool(set_attr(wintypes.HWND(hwnd), ctypes.byref(data)))
    except Exception:
        return False


def apply_macos_liquid_glass(
    widget: QWidget,
    *,
    style: str = "regular",
    corner_radius: float = 0.0,
) -> Any | None:
    """Place native Liquid Glass behind a Qt widget's content on macOS."""
    if platform.system() != "Darwin":
        return None
    try:
        import AppKit
        import objc

        native_view = objc.objc_object(c_void_p=int(widget.winId()))
        frame = native_view.bounds()
        glass_class = getattr(AppKit, "NSGlassEffectView", None)
        if glass_class is not None:
            glass_view = glass_class.alloc().initWithFrame_(frame)
            glass_view.setStyle_(
                getattr(AppKit, "NSGlassEffectViewStyleClear", 1)
                if style == "clear"
                else getattr(AppKit, "NSGlassEffectViewStyleRegular", 0)
            )
            if hasattr(glass_view, "setEffectIsInteractive_"):
                glass_view.setEffectIsInteractive_(False)
            if corner_radius > 0 and hasattr(glass_view, "setCornerRadius_"):
                glass_view.setCornerRadius_(corner_radius)
        else:
            glass_view = AppKit.NSVisualEffectView.alloc().initWithFrame_(frame)
            glass_view.setMaterial_(
                AppKit.NSVisualEffectMaterialSidebar
                if style == "clear"
                else AppKit.NSVisualEffectMaterialHeaderView
            )
            glass_view.setBlendingMode_(AppKit.NSVisualEffectBlendingModeBehindWindow)
            glass_view.setState_(AppKit.NSVisualEffectStateActive)

        glass_view.setAutoresizingMask_(
            AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable
        )
        native_view.addSubview_positioned_relativeTo_(
            glass_view,
            AppKit.NSWindowBelow,
            None,
        )
        return glass_view
    except Exception:
        return None
