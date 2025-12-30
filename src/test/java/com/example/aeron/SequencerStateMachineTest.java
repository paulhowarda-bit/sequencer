package com.example.aeron;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class SequencerStateMachineTest
{
    @Test
    public void testToggleOnce()
    {
        SequencerStateMachine fsm = new SequencerStateMachine();
        assertEquals(SequencerStateMachine.State.CLOSED, fsm.getState());
        SequencerStateMachine.State s = fsm.onToggle();
        assertEquals(SequencerStateMachine.State.OPEN, s);
        assertEquals(SequencerStateMachine.State.OPEN, fsm.getState());
    }

    @Test
    public void testToggleMultiple()
    {
        SequencerStateMachine fsm = new SequencerStateMachine();
        fsm.onToggle();
        fsm.onToggle();
        assertEquals(SequencerStateMachine.State.CLOSED, fsm.getState());
        fsm.processEvent("toggle");
        assertEquals(SequencerStateMachine.State.OPEN, fsm.getState());
    }

    @Test
    public void testUnknownEvent()
    {
        SequencerStateMachine fsm = new SequencerStateMachine();
        assertThrows(IllegalArgumentException.class, () -> fsm.processEvent("unknown"));
    }
}
