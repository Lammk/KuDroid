package android.graphics.drawable;

import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;

/** Draws a bitmap within its bounds using the selected gravity. */
public class BitmapDrawable extends Drawable {
    private Bitmap mBitmap;
    private final Paint mPaint = new Paint();
    private final android.graphics.Rect mDestination = new android.graphics.Rect();
    private int mGravity = 0x77;
    private android.content.res.ColorStateList mTint;
    private android.graphics.PorterDuff.Mode mTintMode = android.graphics.PorterDuff.Mode.SRC_IN;
    private android.graphics.ColorFilter mTintFilter;

    private static Bitmap createDefaultBitmap() {
        return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
    }

    public BitmapDrawable() {
        mBitmap = createDefaultBitmap();
    }

    public BitmapDrawable(Resources res) {
        mBitmap = createDefaultBitmap();
    }

    public BitmapDrawable(Bitmap bitmap) {
        mBitmap = (bitmap != null) ? bitmap : createDefaultBitmap();
    }

    public BitmapDrawable(Resources res, Bitmap bitmap) {
        mBitmap = (bitmap != null) ? bitmap : createDefaultBitmap();
    }

    public BitmapDrawable(String filepath) {
        mBitmap = createDefaultBitmap();
    }

    public BitmapDrawable(Resources res, String filepath) {
        mBitmap = createDefaultBitmap();
    }

    public BitmapDrawable(java.io.InputStream is) {
        mBitmap = createDefaultBitmap();
    }

    public BitmapDrawable(Resources res, java.io.InputStream is) {
        mBitmap = createDefaultBitmap();
    }

    public final Paint getPaint() { return mPaint; }
    public final Bitmap getBitmap() { return mBitmap; }

    public void setBitmap(Bitmap bitmap) {
        mBitmap = (bitmap != null) ? bitmap : createDefaultBitmap();
        invalidateSelf();
    }

    public int getGravity() { return mGravity; }
    public void setGravity(int gravity) {
        if (mGravity != gravity) {
            mGravity = gravity;
            invalidateSelf();
        }
    }
    public void setAntiAlias(boolean aa) { mPaint.setAntiAlias(aa); }
    public void setTargetDensity(int density) {}
    public void setTileModeXY(android.graphics.Shader.TileMode xmode, android.graphics.Shader.TileMode ymode) {}

    @Override
    public void draw(Canvas canvas) {
        if (canvas == null || mBitmap == null || mBitmap.isRecycled()) return;
        final android.graphics.Rect b = getBounds();
        if (b.isEmpty()) return;
        android.view.Gravity.apply(mGravity, getIntrinsicWidth(), getIntrinsicHeight(),
                b, mDestination, getLayoutDirection());
        android.graphics.ColorFilter filter = mPaint.getColorFilter();
        if (filter == null) mPaint.setColorFilter(mTintFilter);
        try {
            canvas.drawBitmap(mBitmap, null, mDestination, mPaint);
        } finally {
            mPaint.setColorFilter(filter);
        }
    }

    @Override
    public void setAlpha(int alpha) { mPaint.setAlpha(alpha); invalidateSelf(); }

    @Override
    public int getAlpha() { return mPaint.getAlpha(); }

    @Override public void setColorFilter(android.graphics.ColorFilter filter) {
        mPaint.setColorFilter(filter); invalidateSelf();
    }
    @Override public android.graphics.ColorFilter getColorFilter() { return mPaint.getColorFilter(); }
    @Override public void setTintList(android.content.res.ColorStateList tint) {
        mTint = tint; updateTint(); invalidateSelf();
    }
    @Override public void setTintMode(android.graphics.PorterDuff.Mode mode) {
        mTintMode = mode; updateTint(); invalidateSelf();
    }
    private void updateTint() {
        mTintFilter = mTint == null || mTintMode == null ? null : new android.graphics.PorterDuffColorFilter(
                mTint.getColorForState(getState(), mTint.getDefaultColor()), mTintMode);
    }
    @Override public boolean isStateful() { return mTint != null && mTint.isStateful(); }
    @Override protected boolean onStateChange(int[] state) {
        if (mTint == null || mTintMode == null) return false;
        int color = mTint.getColorForState(state, mTint.getDefaultColor());
        if (mTintFilter instanceof android.graphics.PorterDuffColorFilter
                && ((android.graphics.PorterDuffColorFilter) mTintFilter).getColor() == color) return false;
        updateTint(); invalidateSelf(); return true;
    }

    @Override
    public int getIntrinsicWidth() { return mBitmap != null ? mBitmap.getWidth() : -1; }

    @Override
    public int getIntrinsicHeight() { return mBitmap != null ? mBitmap.getHeight() : -1; }

    @Override
    public int getOpacity() {
        return mBitmap == null ? android.graphics.PixelFormat.TRANSPARENT
                : android.graphics.PixelFormat.TRANSLUCENT;
    }
}
