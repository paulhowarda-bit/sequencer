package com.example.aeron;

public class SequencerStateMachine {
    public enum State {
        OPEN, CLOSED
    }

    private State state;
    private final int replicaId;

    public SequencerStateMachine() {
        this(0);
    }

    /**
     * Create a sequencer state machine with a replica id for logging.
     * Use id=0 for non-replicated/local instances.
     */
    public SequencerStateMachine(int replicaId) {
        this.state = State.CLOSED;
        this.replicaId = replicaId;
    }

    public synchronized State getState() {
        return state;
    }

    public synchronized State onToggle(long sequenceNumber) {
        State previous = state;
        state = (state == State.OPEN) ? State.CLOSED : State.OPEN;
        System.out.println(
                "[replica-" + replicaId + "] [seq=" + sequenceNumber + "] State changed: " + previous + " -> " + state);
        return state;
    }

    public synchronized State processEvent(String event, long sequenceNumber) {
        System.out.println("[replica-" + replicaId + "] [seq=" + sequenceNumber + "] Event received: " + event);
        if ("toggle".equalsIgnoreCase(event)) {
            return onToggle(sequenceNumber);
        }
        throw new IllegalArgumentException("Unknown event: " + event);
    }

    // Backward compatibility methods for tests without sequence numbers
    public synchronized State onToggle() {
        return onToggle(-1);
    }

    public synchronized State processEvent(String event) {
        return processEvent(event, -1);
    }

    /**
     * Set the current state (used by snapshot restore).
     */
    public synchronized void setState(State state) {
        this.state = state;
    }
}
