import 'package:flutter_test/flutter_test.dart';

import 'package:brenkschat_desktop/config.dart';

void main() {
  test('normalizes server URL', () {
    expect(normalizeServerUrl('brenkschat.ru/'), 'https://brenkschat.ru');
    expect(
        normalizeServerUrl('http://127.0.0.1:3002/'), 'http://127.0.0.1:3002');
  });
}
