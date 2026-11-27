package com.bittr.android.core.designsystem

import org.junit.Assert.assertEquals
import org.junit.Test

class GroupsOfFourTest {

    @Test
    fun `an address splits into groups of four, the last as long as what is left`() {
        assertEquals("bcrt 1ql0 pkt3 du79 00av nxcj usmc jgm3 fvvt kzm2 u6nw", inGroupsOfFour("bcrt1ql0pkt3du7900avnxcjusmcjgm3fvvtkzm2u6nw"))
        assertEquals("bc1q ar0s rrr7 xfkv y5l6 43ly dnw9 re59 gtzz wf5m dq", inGroupsOfFour("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
    }

    @Test
    fun `short text stays one group`() {
        assertEquals("abc", inGroupsOfFour("abc"))
        assertEquals("", inGroupsOfFour(""))
    }
}
