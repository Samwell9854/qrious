import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/registry.dart';
import 'package:qrious/models/qr_field.dart';

/// The registry itself, so registering a format is what enrols it in these
/// checks — there is no second list to keep in step.
final formats = qrFormats;

void main() {
  group('every format', () {
    for (final format in formats) {
      group(format.id, () {
        test('has a non-empty id and name', () {
          expect(format.id, isNotEmpty);
          expect(format.name, isNotEmpty);
        });

        test('declares at least one field, each with a unique id', () {
          expect(format.fields, isNotEmpty);
          final ids = format.fields.map((f) => f.id).toList();
          expect(ids.toSet(), hasLength(ids.length));
        });

        test('gives every dropdown field a non-empty options list', () {
          for (final field in format.fields) {
            if (field.type == QrFieldType.dropdown) {
              expect(
                field.options,
                isNotNull,
                reason: '${field.id} is a dropdown with no options',
              );
              expect(field.options, isNotEmpty);
            }
          }
        });

        test('builds a string from an empty map', () {
          expect(format.buildQrString({}), isA<String>());
        });

        test('builds a string when every field is present but empty', () {
          final values = {for (final f in format.fields) f.id: ''};
          expect(format.buildQrString(values), isA<String>());
        });

        test('builds a string from the home screen initial values', () {
          // What _initControllers seeds the map with before any typing.
          final values = {
            for (final f in format.fields)
              f.id: switch (f.type) {
                QrFieldType.dropdown => f.options!.first,
                QrFieldType.checkbox => 'false',
                _ => '',
              },
          };
          expect(format.buildQrString(values), isA<String>());
        });

        test('has validators that survive an empty value', () {
          // The screen never calls one with an empty string, but a validator
          // that throws on one would turn a stray call into a broken form.
          for (final field in format.fields) {
            expect(
              () => field.validate?.call(''),
              returnsNormally,
              reason: '${field.id} threw on an empty value',
            );
          }
        });

        test('puts validators only on fields that can hold text', () {
          for (final field in format.fields) {
            if (field.validate == null) continue;
            expect(
              field.type,
              isNot(anyOf(QrFieldType.dropdown, QrFieldType.checkbox)),
              reason: '${field.id} cannot be typed into freely',
            );
          }
        });

        test('gives every group parts, and kinds that are distinct', () {
          for (final field in format.fields) {
            if (field.type != QrFieldType.group) continue;
            expect(field.parts, isNotEmpty, reason: '${field.id} has no parts');
            final partIds = field.parts!.map((p) => p.id).toList();
            expect(partIds.toSet(), hasLength(partIds.length));
            expect(partIds, isNot(contains('kind')), reason: 'reserved');
            if (field.kinds == null) continue;
            expect(field.kinds, isNotEmpty);
            final values = field.kinds!.map((k) => k.value).toList();
            expect(values.toSet(), hasLength(values.length));
          }
        });

        test('builds a string with one fresh entry in every group', () {
          // What the screen holds right after each "Add" button is pressed.
          final values = <String, String>{
            for (final f in format.fields)
              if (f.type == QrFieldType.group) ...{
                f.id: '1',
                for (final p in f.parts!) QrEntries.part(f.id, 0, p.id): '',
                if (f.kinds != null)
                  QrEntries.kind(f.id, 0): f.kinds!.first.value,
              },
          };
          expect(format.buildQrString(values), format.buildQrString({}));
        });

        test('has part validators that survive an empty value', () {
          for (final field in format.fields) {
            for (final part in field.parts ?? const <QrField>[]) {
              expect(() => part.validate?.call(''), returnsNormally);
            }
          }
        });

        test('ignores keys it does not declare', () {
          final declared = format.buildQrString({});
          expect(format.buildQrString({'nonsense': 'x'}), declared);
        });
      });
    }
  });
}
