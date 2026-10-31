#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Alpha helpers for the Cocos split-texture masks.

The masks are nearly binary (about 84% zero, 16% 255) with a narrow
antialiased band.  The old build thresholded them to 0/255, which threw that
band away and made every cutout edge hard.  Keep the original 8-bit values
and only clear the low-noise floor.
"""

import numpy as np


def soft_alpha(mask, low=8):
    """8-bit alpha from a grayscale mask, clearing values below ``low``."""
    out = np.asarray(mask, dtype=np.uint8).copy()
    out[out < low] = 0
    return out
