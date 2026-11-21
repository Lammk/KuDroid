package com.google.android.gms.tasks;

import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.Executor;

public final class LegacyTaskAdapter {
    private LegacyTaskAdapter() {}
    private static final Executor MAIN = new Executor() {
        @Override public void execute(Runnable command) {
            Handler handler = new Handler(Looper.getMainLooper());
            if (!handler.post(command)) throw new IllegalStateException("Main looper has stopped");
        }
    };

    public static <T> Task<T> wrap(com.google.android.play.core.tasks.Task<T> task) {
        if (task == null) throw new NullPointerException("task");
        return new AdaptedTask<T>(task);
    }

    private static final class AdaptedTask<T> extends Task<T> {
        private final com.google.android.play.core.tasks.Task<T> delegate;
        AdaptedTask(com.google.android.play.core.tasks.Task<T> delegate) { this.delegate = delegate; }
        @Override public boolean isComplete() { return delegate.isComplete(); }
        @Override public boolean isSuccessful() { return delegate.isSuccessful(); }
        @Override public boolean isCanceled() { return false; }
        @Override public Exception getException() { return delegate.getException(); }
        @Override public T getResult() {
            if (!isComplete()) throw new IllegalStateException("Task is incomplete");
            if (!isSuccessful()) throw new RuntimeExecutionException(getException());
            return delegate.getResult();
        }
        @Override public <X extends Throwable> T getResult(Class<X> type) throws X {
            if (type == null) throw new NullPointerException("exceptionType");
            if (!isComplete()) throw new IllegalStateException("Task is incomplete");
            Exception error = getException();
            if (error != null && type.isInstance(error)) throw type.cast(error);
            return getResult();
        }
        @Override public Task<T> addOnCompleteListener(OnCompleteListener<T> listener) {
            return addOnCompleteListener(MAIN, listener);
        }
        @Override public Task<T> addOnSuccessListener(OnSuccessListener<? super T> listener) {
            return addOnSuccessListener(MAIN, listener);
        }
        @Override public Task<T> addOnFailureListener(OnFailureListener listener) {
            return addOnFailureListener(MAIN, listener);
        }
        @Override public Task<T> addOnCompleteListener(final Executor executor, final OnCompleteListener<T> listener) {
            if (executor == null || listener == null) throw new NullPointerException();
            delegate.addOnCompleteListener(new com.google.android.play.core.tasks.OnCompleteListener<T>() {
                @Override public void onComplete(com.google.android.play.core.tasks.Task<T> task) {
                    executor.execute(new Runnable() {
                        @Override public void run() { listener.onComplete(AdaptedTask.this); }
                    });
                }
            });
            return this;
        }
        @Override public Task<T> addOnSuccessListener(final Executor executor, final OnSuccessListener<? super T> listener) {
            if (executor == null || listener == null) throw new NullPointerException();
            delegate.addOnSuccessListener(new com.google.android.play.core.tasks.OnSuccessListener<T>() {
                @Override public void onSuccess(final T value) {
                    executor.execute(new Runnable() { @Override public void run() { listener.onSuccess(value); } });
                }
            });
            return this;
        }
        @Override public Task<T> addOnFailureListener(final Executor executor, final OnFailureListener listener) {
            if (executor == null || listener == null) throw new NullPointerException();
            delegate.addOnFailureListener(new com.google.android.play.core.tasks.OnFailureListener() {
                @Override public void onFailure(final Exception error) {
                    executor.execute(new Runnable() { @Override public void run() { listener.onFailure(error); } });
                }
            });
            return this;
        }
    }
}
