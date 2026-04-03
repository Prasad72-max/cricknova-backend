# Razorpay / R8 rules
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# Some Razorpay SDK builds reference this optional annotation at shrink time.
-dontwarn proguard.annotation.Keep

# Preserve annotation metadata and JS bridge methods used by checkout WebView.
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
