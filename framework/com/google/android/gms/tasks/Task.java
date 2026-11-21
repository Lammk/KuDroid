package com.google.android.gms.tasks;

import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.Executor;

public abstract class Task<TResult> {
    private static final Executor MAIN = new Executor() {
        @Override public void execute(Runnable command) {
            Handler handler = new Handler(Looper.getMainLooper());
            if (!handler.post(command)) throw new IllegalStateException("Main looper has stopped");
        }
    };

    public abstract boolean isComplete();
    public abstract boolean isSuccessful();
    public abstract boolean isCanceled();
    public abstract TResult getResult();
    public abstract <X extends Throwable> TResult getResult(Class<X> exceptionType) throws X;
    public abstract Exception getException();
    public abstract Task<TResult> addOnCompleteListener(Executor executor, OnCompleteListener<TResult> listener);
    public abstract Task<TResult> addOnSuccessListener(Executor executor, OnSuccessListener<? super TResult> listener);
    public abstract Task<TResult> addOnFailureListener(Executor executor, OnFailureListener listener);

    public Task<TResult> addOnCompleteListener(OnCompleteListener<TResult> listener) {
        return addOnCompleteListener(MAIN, listener);
    }
    public Task<TResult> addOnSuccessListener(OnSuccessListener<? super TResult> listener) {
        return addOnSuccessListener(MAIN, listener);
    }
    public Task<TResult> addOnFailureListener(OnFailureListener listener) {
        return addOnFailureListener(MAIN, listener);
    }
}
