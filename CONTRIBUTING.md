# Contributing to AeroPad

Thank you for your interest in contributing to **AeroPad**! We welcome contributions from developers, designers, and tech enthusiasts.

## How to Contribute

### Reporting Bugs
If you encounter any issues or bugs while testing on your device:
1. Check the [GitHub Issues](https://github.com/abhi963007/Aeropad-/issues) tab to see if the issue has already been reported.
2. If not, open a new issue with:
   - Your Android device model and Android OS version.
   - The host OS (e.g. Windows 11 23H2, macOS Sonoma).
   - Clear steps to reproduce the problem.

### Feature Suggestions
Have an idea for a cool feature (e.g., Gyro Air Mouse, Media Remote, Presentation clicker)?
- Open a feature request under [Issues](https://github.com/abhi963007/Aeropad-/issues).

### Pull Request Workflow
1. **Fork** the repository to your own GitHub account.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/<your-username>/Aeropad-.git
   ```
3. Create a descriptive topic branch:
   ```bash
   git checkout -b feature/awesome-gesture
   ```
4. Commit your changes with clear, concise messages:
   ```bash
   git commit -m "feat: implement two-finger horizontal scroll"
   ```
5. Push to your branch:
   ```bash
   git push origin feature/awesome-gesture
   ```
6. Submit a **Pull Request** targeting the `main` branch.

---

## Code Style & Guidelines
- Write clean, idiomatic **Dart** code and format changes with `dart format`.
- Keep Flutter UI and gesture logic in `lib/`.
- Keep Android-only Bluetooth HID code in `android/app/src/main/kotlin/` behind the existing platform channels.
- Run `flutter analyze` and `flutter test` before opening a pull request.
- Ensure Bluetooth HID descriptors strictly comply with USB-IF HID standards.

Thank you for helping make AeroPad better!
