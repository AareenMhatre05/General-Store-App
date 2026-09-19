/// Identifies the build that is actually running.
///
/// Exists because "that feature isn't there" and "you're running an older
/// APK" look identical from the outside, and we lost a round of debugging
/// to exactly that. Both apps show this on screen, so the first question
/// is answerable in two seconds instead of by grepping a binary.
///
/// Updated by the build script (`tool/stamp_build.sh`), not by hand.
const String kBuildStamp = '2026-08-23 15:34';
