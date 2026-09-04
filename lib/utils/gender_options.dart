import '../services/locale_service.dart';

/// Canonical values stored in `profiles.gender` — stable across locales
/// (the picker only ever assigns one of these), so a value saved while the
/// app was in one language still displays correctly after switching to
/// another. Use [genderLabel] to show the translated label for one of
/// these.
const genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

const _labelKeys = {
  'Male': 'auth_gender_male',
  'Female': 'auth_gender_female',
  'Other': 'auth_gender_other',
  'Prefer not to say': 'auth_gender_prefer_not_to_say',
};

String genderLabel(String value) => tr(_labelKeys[value] ?? value);
