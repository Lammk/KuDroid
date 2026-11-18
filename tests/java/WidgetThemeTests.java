import android.content.Context;
import android.content.res.Resources;
import android.graphics.drawable.ColorDrawable;
import android.util.TypedValue;
import android.view.ContextThemeWrapper;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;

public final class WidgetThemeTests {
    private static int checks;
    private static void check(boolean value, String name) {
        System.out.flush();
        if (!value) throw new AssertionError(name);
        ++checks;
        System.out.println("PASS " + name);
    }
    private static final class Icon extends ColorDrawable {
        Icon() { super(0xFF000000); }
        public int getIntrinsicWidth() { return 20; }
        public int getIntrinsicHeight() { return 16; }
    }
    public static int run() {
        checks = 0;
        check(Resources.selectSystemTheme(7, 1, 1, 2, 3, 4) == 7, "explicit theme is retained");
        check(Resources.selectSystemTheme(0, 10, 1, 2, 3, 4) == 1, "legacy target uses original theme");
        check(Resources.selectSystemTheme(0, 11, 1, 2, 3, 4) == 2, "first modern target selects its theme");
        check(Resources.selectSystemTheme(0, 14, 1, 2, 3, 4) == 3, "intermediate target selects its theme");
        check(Resources.selectSystemTheme(0, 24, 1, 2, 3, 4) == 4, "current target selects its theme");
        ContextThemeWrapper context = new ContextThemeWrapper(new android.app.ApplicationContext("widget.fixture"), 0);
        Resources.Theme theme = context.getTheme();
        check(context.getThemeResId() != 0, "unspecified theme receives a system default");
        TypedValue background = new TypedValue();
        check(theme.resolveAttribute(com.android.internal.R.attr.windowBackground, background, true),
                "default theme supplies a window background");
        Button button = new Button(context);
        TypedValue buttonStyle = new TypedValue();
        theme.resolveAttribute(com.android.internal.R.attr.buttonStyle, buttonStyle, true);
        android.content.res.TypedArray buttonAttrs = context.obtainStyledAttributes(null,
                com.android.internal.R.styleable.View, com.android.internal.R.attr.buttonStyle, 0);
        System.out.println("Button style=" + buttonStyle.resourceId + " background="
                + buttonAttrs.getResourceId(com.android.internal.R.styleable.View_background, 0));
        check(button.getBackground() != null, "button constructor applies its default style: type="
                + buttonStyle.type + " data=" + buttonStyle.data + " bg="
                + buttonAttrs.getResourceId(com.android.internal.R.styleable.View_background, 0));
        button.setTextColor(0xFF123456);
        check(button.getCurrentTextColor() == 0xFF123456, "explicit text color overrides themed color");
        button.setBackgroundDrawable(null);
        check(button.getBackground() == null, "explicitly cleared button background stays transparent");
        CheckBox checkbox = new CheckBox(context);
        check(checkbox.getButtonDrawable() != null, "checkbox constructor applies its default indicator");
        checkbox.setButtonDrawable(new Icon());
        checkbox.setPadding(3, 0, 4, 0);
        check(checkbox.getCompoundPaddingLeft() == 23 && checkbox.getCompoundPaddingRight() == 4,
                "indicator reserves space before text");
        checkbox.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        check(checkbox.getCompoundPaddingLeft() == 3 && checkbox.getCompoundPaddingRight() == 24,
                "indicator padding follows layout direction");
        final int[] events = new int[1];
        checkbox.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            public void onCheckedChanged(CompoundButton button, boolean value) {
                ++events[0];
                button.setChecked(!value);
            }
        });
        checkbox.performClick();
        check(events[0] == 1 && !checkbox.isChecked(), "listener reentry changes state without recursive notification");
        checkbox.setOnCheckedChangeListener(null);
        checkbox.performClick();
        check(checkbox.isChecked(), "click toggles checked state without a click listener");
        boolean checked = false;
        for (int state : checkbox.getDrawableState()) checked |= state == com.android.internal.R.attr.state_checked;
        check(checked, "checked state reaches drawable selectors");
        checkbox.setText("");
        checkbox.measure(View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.AT_MOST));
        check(checkbox.getMeasuredWidth() >= 27 && checkbox.getMeasuredHeight() >= 16,
                "empty label retains measurable indicator geometry");
        return checks;
    }
}
