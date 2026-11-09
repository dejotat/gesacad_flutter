import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/helpers/file_viewer_helper.dart';

void main() {
  test('repara nombres guardados con la codificación torcida y deja intactos los correctos', () {
    expect(FileViewerHelper.repararNombre('PÃ³ster Conecta JambalÃ¡.pdf'), 'Póster Conecta Jambalá.pdf');
    expect(FileViewerHelper.repararNombre('Café.pdf'), 'Café.pdf');
    expect(FileViewerHelper.repararNombre('informe final.pdf'), 'informe final.pdf');
    expect(FileViewerHelper.repararNombre('日本語.pdf'), '日本語.pdf');
  });

  test('extractName aplica la reparación al formato url::name::nombre', () {
    expect(FileViewerHelper.extractName('https://res.cloudinary.com/x/raw/upload/1_Pster.pdf::name::PÃ³ster.pdf'), 'Póster.pdf');
  });
}
