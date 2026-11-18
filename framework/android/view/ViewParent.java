package android.view;

import android.graphics.Rect;

/** Provide callbacks for a view parent. */













public interface ViewParent {
    /** The parent of this parent, or null at the root of the hierarchy. */
    ViewParent getParent();

    /** A child wants to be measured and laid out again. */
    void requestLayout();

    /** True once a requestLayout is pending and not yet served. */
    boolean isLayoutRequested();

    /** A child's content changed within the given rectangle. */
    void invalidateChild(View child, Rect r);

    /** Ask ancestors to stop intercepting touch events for the current gesture. */







    void requestDisallowInterceptTouchEvent(boolean disallowIntercept);

    /** Focus is moving to `child`; ancestors may need to scroll it into view. */
    void requestChildFocus(View child, View focused);

    /** `child` no longer holds focus. */
    void clearChildFocus(View child);

    /** The view that currently holds focus in this subtree, or null. */
    View focusSearch(View v, int direction);

    /** A child asks for the given rectangle (in its coordinates) to be brought on screen. */
    boolean requestChildRectangleOnScreen(View child, Rect rectangle, boolean immediate);

    /** A child's transient state (an animation in flight, say) changed. */
    void childHasTransientStateChanged(View child, boolean hasTransientState);

    /** A child's drawable state changed. */
    void childDrawableStateChanged(View child);

    /** Brings a child to the front of the drawing order. */
    void bringChildToFront(View child);

    /** Computes the part of a child's rectangle that is visible in this parent's ancestry. */
    boolean getChildVisibleRect(View child, Rect r, android.graphics.Point offset);

    void requestTransparentRegion(View child);

    void recomputeViewAttributes(View child);

    boolean showContextMenuForChild(View originalView);

    android.view.ActionMode startActionModeForChild(View originalView,
            android.view.ActionMode.Callback callback, int type);

    void notifySubtreeAccessibilityStateChanged(View child, View source, int changeType);

    /** Nested scrolling: a descendant starts a scroll this parent may take part in. */
    boolean onStartNestedScroll(View child, View target, int nestedScrollAxes);

    void onNestedScrollAccepted(View child, View target, int nestedScrollAxes);

    void onStopNestedScroll(View target);

    void onNestedScroll(View target, int dxConsumed, int dyConsumed, int dxUnconsumed,
            int dyUnconsumed);

    void onNestedPreScroll(View target, int dx, int dy, int[] consumed);

    boolean onNestedFling(View target, float velocityX, float velocityY, boolean consumed);

    boolean onNestedPreFling(View target, float velocityX, float velocityY);

    boolean onNestedPrePerformAccessibilityAction(View target, int action, android.os.Bundle arguments);
}
