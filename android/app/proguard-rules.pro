# ProGuard/R8 rules for the lunarlog release build (issue #211).
#
# The Flutter Gradle plugin already appends its own flutter_proguard_rules.pro
# and AGP's proguard-android-optimize.txt; the rules here are the app's own
# additions. Every rule below exists because something reaches a class through
# a channel R8 cannot see (JNI, reflection, Gson) — do not add speculative
# keeps; prefer proving a crash first and narrowing the rule to what it needs.
#
# Verified by a local `flutter build apk --release --obfuscate
# --split-debug-info=build/symbols` on this tree (issue #211) — the build must
# keep succeeding and the internal-track smoke run (app launch, sync, entry
# log, push, reminder delivery) is the functional gate before production.

# ---------------------------------------------------------------------------
# Flutter engine (JNI bridge)
# ---------------------------------------------------------------------------
# The engine's native code (libflutter.so) resolves Java methods of the
# embedding by name through RegisterNatives, a channel R8 cannot trace.
# flutter_proguard_rules.pro only keeps FlutterPlugin implementations; this
# covers the embedding itself.
-keep class io.flutter.** { *; }

# Keeping the embedding drags in FlutterPlayStoreSplitApplication /
# PlayStoreDeferredComponentManager, which reference Play Core -- a
# compile-only dependency this app never ships because it uses no deferred
# components. Found by the first minified build (R8's missing_rules.txt,
# issue #211); the blanket dontwarn is safe because those classes are never
# instantiated when the manifest's application class is not a
# FlutterPlayStoreSplitApplication.
-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# Drift / sqlite3 (native bindings)
# ---------------------------------------------------------------------------
# Deliberately NO keep rules here: drift's NativeDatabase talks to sqlite3
# through dart:ffi (DynamicLibrary.open of the system libsqlite3.so), which
# never crosses JNI and cannot be broken by R8 renaming. If this app ever
# gains a Java/JNI-backed database layer (e.g. sqflite or an SQLCipher AAR),
# add the keeps its docs require at that point.

# ---------------------------------------------------------------------------
# Firebase Messaging (issue #5 caregiver alerts)
# ---------------------------------------------------------------------------
# firebase-messaging's AARs ship consumer rules, and the plugin's service and
# receivers are manifest components (kept automatically via the merged
# manifest). Kept defensively because the plugin is only linked in
# Firebase-configured builds — a broken keep here would surface as silent
# notification loss, not a startup crash, on exactly the builds that use it.
-keep class io.flutter.plugins.firebase.messaging.** { *; }
-keep class com.google.firebase.messaging.** { *; }

# ---------------------------------------------------------------------------
# flutter_local_notifications (Gson reflection)
# ---------------------------------------------------------------------------
# The plugin serializes NotificationDetails models into the AlarmManager
# intent extras with Gson's reflective adapter (and RuntimeTypeAdapterFactory),
# so R8 stripping or renaming the model classes/fields breaks scheduled
# reminders at delivery time — a failure that only shows up when a reminder
# fires. The plugin ships no consumer proguard rules of its own.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature

# ---------------------------------------------------------------------------
# Retrace quality (ProGuard mapping + Sentry, issue #211)
# ---------------------------------------------------------------------------
# Keep line numbers so the uploaded mapping.txt retraces stack traces with
# original line numbers instead of bare methods.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
