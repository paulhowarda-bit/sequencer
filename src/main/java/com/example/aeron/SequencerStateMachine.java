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

    public synchronized State onToggle() {
        State previous = state;
        state = (state == State.OPEN) ? State.CLOSED : State.OPEN;
        System.out.println("[replica-" + replicaId + "] State changed: " + previous + " -> " + state);
        return state;
    }

    public synchronized State processEvent(String event) {
        System.out.println("[replica-" + replicaId + "] Event received: " + event);
        if ("toggle".equalsIgnoreCase(event)) {
            return onToggle();
        }
        throw new IllegalArgumentException("Unknown event: " + event);
    }

    /**
     * Set the current state (used by snapshot restore).
     */
    public synchronized void setState(State state) {
        this.state = state;
    }
}
