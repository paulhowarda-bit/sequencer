package com.example.aeron;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class ReplicatedSequencerTest {

    @Test
    public void testReplicationToggle() {
        ReplicatedSequencer rs = new ReplicatedSequencer(3);
        // initial state should be CLOSED for all replicas
        for (SequencerStateMachine.State s : rs.getStates()) {
            assertEquals(SequencerStateMachine.State.CLOSED, s);
        }

        rs.sendEvent("toggle");
        for (SequencerStateMachine.State s : rs.getStates()) {
            assertEquals(SequencerStateMachine.State.OPEN, s);
        }

        rs.sendEvent("toggle");
        for (SequencerStateMachine.State s : rs.getStates()) {
            assertEquals(SequencerStateMachine.State.CLOSED, s);
        }

        rs.shutdown();
    }

    @Test
    public void testReplicationUnknownEvent() {
        ReplicatedSequencer rs = new ReplicatedSequencer(3);
        assertThrows(RuntimeException.class, () -> rs.sendEvent("unknown"));
        rs.shutdown();
    }
}
