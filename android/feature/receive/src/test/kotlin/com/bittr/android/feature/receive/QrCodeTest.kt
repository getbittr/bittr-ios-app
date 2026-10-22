package com.bittr.android.feature.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QrCodeTest {

    @Test
    fun `the logo's box is odd or even like the code, about 13 percent of it, and clear of the finder patterns`() {
        // Every QR version, 21 to 177 modules.
        for (modules in 21..177 step 4) {
            val box = logoModules(modules)
            assertEquals("Centred on the grid at $modules modules", modules % 2, box % 2)
            assertTrue("At least 13 % at $modules modules", box >= modules * 0.13)
            assertTrue("At most a module over 13 %, plus parity, at $modules modules", box <= modules * 0.13 + 2)
            // The finder patterns are 7 modules square in three corners, and a separator row beside them.
            assertTrue("Clear of the finder patterns at $modules modules", (modules - box) / 2 >= 8)
        }
    }
}
