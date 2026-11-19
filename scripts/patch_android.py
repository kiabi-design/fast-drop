import re
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    text = manifest.read_text(encoding="utf-8")
    perms = """
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
"""
    if "MANAGE_EXTERNAL_STORAGE" not in text:
        text = text.replace("<application", perms + "\n    <application", 1)
        manifest.write_text(text, encoding="utf-8")

wrapper = Path("android/gradle/wrapper/gradle-wrapper.properties")
if wrapper.exists():
    w_text = wrapper.read_text(encoding="utf-8")
    w_text = re.sub(
        r"distributionUrl=.*",
        r"distributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-bin.zip",
        w_text,
    )
    wrapper.write_text(w_text, encoding="utf-8")

settings_gradle = Path("android/settings.gradle")
if settings_gradle.exists():
    s_text = settings_gradle.read_text(encoding="utf-8")
    s_text = re.sub(r'id "com\.android\.application" version "[^"]+"', 'id "com.android.application" version "8.6.0"', s_text)
    s_text = re.sub(r'id "org\.jetbrains\.kotlin\.android" version "[^"]+"', 'id "org.jetbrains.kotlin.android" version "2.0.20"', s_text)
    settings_gradle.write_text(s_text, encoding="utf-8")

for gradle_file in [Path("android/app/build.gradle"), Path("android/app/build.gradle.kts")]:
    if gradle_file.exists():
        g_text = gradle_file.read_text(encoding="utf-8")
        g_text = re.sub(r"compileSdk\s*=?\s*(flutter\.compileSdkVersion|\d+)", "compileSdk = 35", g_text)
        g_text = re.sub(r'ndkVersion\s*=?\s*(flutter\.ndkVersion|"[^"]+")', 'ndkVersion = "26.1.10909125"', g_text)
        gradle_file.write_text(g_text, encoding="utf-8")
