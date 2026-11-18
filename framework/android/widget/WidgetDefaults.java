package android.widget;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.util.AttributeSet;
import android.util.TypedValue;

final class WidgetDefaults {
    private WidgetDefaults() {}

    static boolean usesFrameworkStyle(Context context, AttributeSet attrs, int style, int resource) {
        if (context == null || resource != 0 || (attrs != null && attrs.getStyleAttribute() != 0)) return false;
        TypedValue value = new TypedValue();
        return context.getTheme().resolveAttribute(style, value, false)
                && value.type == TypedValue.TYPE_REFERENCE && (value.data >>> 24) == 1;
    }

    static boolean hasAttribute(AttributeSet attrs, int id) {
        if (attrs == null) return false;
        for (int i = 0; i < attrs.getAttributeCount(); i++) {
            if (attrs.getAttributeNameResource(i) == id) return true;
        }
        return false;
    }

    static int color(Context context, int attribute, int defaultColor) {
        TypedValue value = new TypedValue();
        if (context.getTheme().resolveAttribute(attribute, value, true)
                && value.type >= TypedValue.TYPE_FIRST_COLOR_INT
                && value.type <= TypedValue.TYPE_LAST_COLOR_INT) return value.data;
        return defaultColor;
    }

    static Drawable checkIndicator(Context context) { return new CheckIndicator(context); }

    private static final class CheckIndicator extends Drawable {
        private final Paint paint = new Paint();
        private final int size;
        private final float density;
        private final int normal, active;
        private boolean checked;
        private int alpha = 255;

        CheckIndicator(Context context) {
            paint.setAntiAlias(true);
            density = context.getResources().getDisplayMetrics().density;
            size = Math.round(32 * density);
            normal = color(context, com.android.internal.R.attr.colorControlNormal, 0xFF666666);
            active = color(context, com.android.internal.R.attr.colorControlActivated, 0xFF009688);
        }
        @Override public int getIntrinsicWidth() { return size; }
        @Override public int getIntrinsicHeight() { return size; }
        @Override public boolean isStateful() { return true; }
        @Override public void setAlpha(int value) { alpha = Math.max(0, Math.min(255, value)); invalidateSelf(); }
        @Override public int getAlpha() { return alpha; }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
        @Override protected boolean onStateChange(int[] state) {
            boolean next = false;
            for (int value : state) next |= value == com.android.internal.R.attr.state_checked;
            if (next == checked) return false;
            checked = next;
            invalidateSelf();
            return true;
        }
        @Override public void draw(Canvas canvas) {
            Rect bounds = getBounds();
            float left = bounds.left + 7 * density, top = bounds.top + 7 * density;
            float right = bounds.right - 7 * density, bottom = bounds.bottom - 7 * density;
            paint.setColor(checked ? active : normal);
            paint.setAlpha(alpha);
            paint.setStyle(checked ? Paint.Style.FILL : Paint.Style.STROKE);
            paint.setStrokeWidth(2 * density);
            canvas.drawRect(left, top, right, bottom, paint);
            if (checked) {
                paint.setColor(0xFFFFFFFF);
                paint.setAlpha(alpha);
                paint.setStyle(Paint.Style.STROKE);
                canvas.drawLine(left + 3 * density, top + 9 * density,
                        left + 7 * density, top + 13 * density, paint);
                canvas.drawLine(left + 7 * density, top + 13 * density,
                        left + 15 * density, top + 5 * density, paint);
            }
        }
    }
}
