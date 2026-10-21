import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/integrations/canvas.dart';
void main() {
  test('rejects credential URLs, plaintext and path URLs', () {
    for(final url in ['http://school.edu', 'https://user:token@school.edu', 'https://school.edu/path', 'invalid']) {
      expect(() => CanvasProvider.validateUrl(url), throwsException);
    }
    expect(CanvasProvider.validateUrl('https://school.instructure.com').host, 'school.instructure.com');
  });
}
