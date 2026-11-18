package android.widget;

import android.content.Context;

public abstract class CompoundButton extends Button implements Checkable {
    private boolean mChecked = false;
    public interface OnCheckedChangeListener {
        void onCheckedChanged(CompoundButton buttonView, boolean isChecked);
    }
    private OnCheckedChangeListener mOnCheckedChangeListener;
    private boolean mBroadcasting;

    public CompoundButton(Context context) { this(context, null); }
    public CompoundButton(Context context, android.util.AttributeSet attrs) { this(context, attrs, 0); }
    public CompoundButton(Context context, android.util.AttributeSet attrs, int defStyleAttr) {
        this(context, attrs, defStyleAttr, 0);
    }
    public CompoundButton(Context context, android.util.AttributeSet attrs, int defStyleAttr,
            int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
        android.content.res.TypedArray a = context.obtainStyledAttributes(attrs,
                com.android.internal.R.styleable.CompoundButton, defStyleAttr, defStyleRes);
        try {
            setButtonDrawable(a.getDrawable(com.android.internal.R.styleable.CompoundButton_button));
            setChecked(a.getBoolean(com.android.internal.R.styleable.CompoundButton_checked, false));
        } finally { a.recycle(); }
    }
    public boolean isChecked() { return mChecked; }
    public void setChecked(boolean checked) {
        if (mChecked != checked) {
            mChecked = checked;
            refreshDrawableState();
            invalidate();
            if (mBroadcasting) return;
            mBroadcasting = true;
            try {
                if (mOnCheckedChangeListener != null) mOnCheckedChangeListener.onCheckedChanged(this, mChecked);
            } finally { mBroadcasting = false; }
        }
    }
    public void toggle() { setChecked(!mChecked); }
    private android.graphics.drawable.Drawable mButtonDrawable;
    private int mButtonResource;

    public void setButtonDrawable(int resId) {
        if (resId != 0 && resId == mButtonResource) return;
        mButtonResource = resId;
        android.graphics.drawable.Drawable d = null;
        if (mButtonResource != 0) {
            d = getContext().getDrawable(mButtonResource);
        }
        setButtonDrawable(d);
    }

    public void setButtonDrawable(android.graphics.drawable.Drawable drawable) {
        if (mButtonDrawable != drawable) {
            if (mButtonDrawable != null) {
                mButtonDrawable.setCallback(null);
                unscheduleDrawable(mButtonDrawable);
            }
            mButtonDrawable = drawable;
            if (drawable != null) {
                drawable.setCallback(this);
                drawable.setState(getDrawableState());
                setMinHeight(drawable.getIntrinsicHeight());
            }
            refreshDrawableState();
            requestLayout();
            invalidate();
        }
    }

    public android.graphics.drawable.Drawable getButtonDrawable() {
        return mButtonDrawable;
    }

    public void setOnCheckedChangeListener(OnCheckedChangeListener listener) {
        mOnCheckedChangeListener = listener;
    }

    @Override public boolean performClick() {
        toggle();
        return super.performClick();
    }

    @Override public int getCompoundPaddingLeft() {
        return super.getCompoundPaddingLeft() + (getLayoutDirection() != LAYOUT_DIRECTION_RTL && mButtonDrawable != null
                ? Math.max(0, mButtonDrawable.getIntrinsicWidth()) : 0);
    }

    @Override public int getCompoundPaddingRight() {
        return super.getCompoundPaddingRight() + (getLayoutDirection() == LAYOUT_DIRECTION_RTL && mButtonDrawable != null
                ? Math.max(0, mButtonDrawable.getIntrinsicWidth()) : 0);
    }

    @Override protected int[] onCreateDrawableState(int extraSpace) {
        int[] state = super.onCreateDrawableState(extraSpace + 1);
        if (mChecked) mergeDrawableStates(state, new int[]{com.android.internal.R.attr.state_checked});
        return state;
    }

    @Override protected void drawableStateChanged() {
        super.drawableStateChanged();
        if (mButtonDrawable != null && mButtonDrawable.setState(getDrawableState())) invalidate();
    }

    @Override protected boolean verifyDrawable(android.graphics.drawable.Drawable drawable) {
        return drawable == mButtonDrawable || super.verifyDrawable(drawable);
    }

    @Override protected void onDraw(android.graphics.Canvas canvas) {
        super.onDraw(canvas);
        if (canvas == null || mButtonDrawable == null) return;
        int width = Math.max(0, mButtonDrawable.getIntrinsicWidth());
        int height = Math.max(0, mButtonDrawable.getIntrinsicHeight());
        int top = 0;
        int gravity = getGravity() & android.view.Gravity.VERTICAL_GRAVITY_MASK;
        if (gravity == android.view.Gravity.BOTTOM) top = getHeight() - height;
        else if (gravity == android.view.Gravity.CENTER_VERTICAL) top = (getHeight() - height) / 2;
        int left = getLayoutDirection() == LAYOUT_DIRECTION_RTL ? getWidth() - width : 0;
        mButtonDrawable.setBounds(left, top, left + width, top + height);
        mButtonDrawable.draw(canvas);
    }
}
