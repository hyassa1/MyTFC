# Règles R8 pour MonTFC.
# Flutter fournit ses propres règles ; on conserve ici uniquement ce que les
# plugins utilisés par réflexion pourraient perdre.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
