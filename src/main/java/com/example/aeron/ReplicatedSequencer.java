package com.example.aeron;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class ReplicatedSequencer {
    private final List<SequencerStateMachine> replicas;
    private final ExecutorService executor;

    public ReplicatedSequencer(int replicaCount) {
        if (replicaCount < 1) {
            throw new IllegalArgumentException("replicaCount must be >= 1");
        }
        this.replicas = new ArrayList<>(replicaCount);
        for (int i = 0; i < replicaCount; i++) {
            // replicas numbered from 1..N for clearer logs
            replicas.add(new SequencerStateMachine(i + 1));
        }
        this.executor = Executors.newFixedThreadPool(replicaCount);
    }

    /**
     * Apply an event to all replicas and return their resulting states.
     * This blocks until all replicas have processed the event.
     */
    public List<SequencerStateMachine.State> sendEvent(String event) {
        List<Callable<SequencerStateMachine.State>> tasks = new ArrayList<>();
        for (SequencerStateMachine r : replicas) {
            tasks.add(() -> r.processEvent(event));
        }

        try {
            List<Future<SequencerStateMachine.State>> futures = executor.invokeAll(tasks);
            List<SequencerStateMachine.State> states = new ArrayList<>(futures.size());
            for (Future<SequencerStateMachine.State> f : futures) {
                states.add(f.get());
            }
            return states;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException(e);
        } catch (ExecutionException e) {
            throw new RuntimeException(e.getCause());
        }
    }

    public List<SequencerStateMachine.State> getStates() {
        List<SequencerStateMachine.State> states = new ArrayList<>(replicas.size());
        for (SequencerStateMachine r : replicas) {
            states.add(r.getState());
        }
        return states;
    }

    public void shutdown() {
        executor.shutdownNow();
    }

    public int replicaCount() {
        return replicas.size();
    }
}
