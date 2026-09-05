import '../services/locale_service.dart';

const genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

const _labelKeys = {
  'Male': 'auth_gender_male',
  'Female': 'auth_gender_female',
  'Other': 'auth_gender_other',
  'Prefer not to say': 'auth_gender_prefer_not_to_say',
};

String genderLabel(String value) => tr(_labelKeys[value] ?? value);
