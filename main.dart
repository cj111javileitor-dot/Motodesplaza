name: Build APK

on:
  push:
    branches: [ main, master, principal ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: Motodesplaza
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - run: flutter pub get

      - name: Crear plataforma Android
        run: flutter create . --platforms=android --overwrite

      - run: flutter build apk --debug

      - uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: Motodesplaza/build/app/outputs/flutter-apk/app-debug.apk
