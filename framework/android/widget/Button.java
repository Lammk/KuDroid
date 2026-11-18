package android.widget;

import android.content.Context;

/** Provide a clickable text control. */




public class Button extends TextView {
    public Button(Context context) {
        this(context, null);
    }

    public Button(Context context, android.util.AttributeSet attrs) {
        this(context, attrs, com.android.internal.R.attr.buttonStyle);
    }

    public Button(Context context, android.util.AttributeSet attrs, int defStyleAttr) {
        this(context, attrs, defStyleAttr, 0);
    }

    public Button(Context context, android.util.AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
        if (getBackground() == null && defStyleAttr == com.android.internal.R.attr.buttonStyle
                && WidgetDefaults.usesFrameworkStyle(context, attrs, defStyleAttr, defStyleRes)
                && !WidgetDefaults.hasAttribute(attrs, com.android.internal.R.attr.background)) {
            setBackgroundColor(WidgetDefaults.color(context,
                    com.android.internal.R.attr.colorButtonNormal, 0xFFE0E0E0));
        }
        if (getGravity() == 0) setGravity(android.view.Gravity.CENTER);
    }

}
