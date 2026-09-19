$p = "android\app\src\main\AndroidManifest.xml"
$t = Get-Content $p -Raw
if ($t -notmatch "ACCESS_FINE_LOCATION") {
  $nl = [Environment]::NewLine
  $perm = '<uses-permission android:name="android.permission.INTERNET"/>' + $nl +
          '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>' + $nl +
          '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>' + $nl +
          '    <application'
  $t = $t -replace '<application', $perm
  Set-Content -Path $p -Value $t -NoNewline
}
