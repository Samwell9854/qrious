import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';
import 'parsing.dart';

class SmsFormat extends QrFormat {
  @override
  String get id => 'sms';

  @override
  String get name => 'Text Message (SMS)';

  @override
  QrFormatGroup get group => QrFormatGroup.message;

  @override
  IconData get icon => Icons.sms_outlined;

  /// The two ways a code can ask for a text message, as the expert dropdown offers
  /// them. The first is the default, and the only one beginner mode writes.
  static const smsto = 'SMSTO:';
  static const smsUri = 'sms:';

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'form',
      label: 'Payload Form',
      type: QrFieldType.dropdown,
      options: [smsto, smsUri],
      expert: true,
    ),
    QrField(
      id: 'phone',
      label: 'Phone Number',
      required: true,
      hint: '+1 555 000 0000',
      validate: validateSmsNumber,
    ),
    _recipients,
    QrField(
      id: 'apple',
      label: 'Write for Apple devices',
      type: QrFieldType.checkbox,
      hint:
          'With several numbers, iPhone and Mac open all of them only this '
          'way; Android then finds none',
      expert: true,
      showWhen: (field: 'form', value: smsUri),
    ),
    QrField(id: 'message', label: 'Message', type: QrFieldType.multiline),
  ];

  /// Apple's own way to give several recipients, which no spec defines. Messages on
  /// iPhone opens only the first number of the standard comma list, and opens all of
  /// them this way; Android reads `open` as the number and finds none.
  static const _appleOpen = 'sms://open?addresses=';

  // Only `sms:` can carry more than one recipient.
  static const _recipients = QrField(
    id: 'recipients',
    label: 'Recipient',
    type: QrFieldType.group,
    parts: [
      QrField(
        id: 'number',
        label: 'Phone Number',
        hint: '+1 555 000 0000',
        validate: validateSmsNumber,
      ),
    ],
    expert: true,
    showWhen: (field: 'form', value: smsUri),
  );

  /// An SMS number: what a phone number may hold, less the pause. A comma separates
  /// the recipients of an `sms:` URI, and a pause means nothing to a text message.
  static String? validateSmsNumber(String value) => value.contains(',')
      ? 'A text message number takes no pause (,)'
      : validatePhone(value);

  /// `SMSTO:<number>:<message>`, the form ZXing introduced and phone cameras read.
  /// Nothing in the message needs escaping: a reader splits at the first colon
  /// after the number, and the number cannot hold one.
  ///
  /// Or, in expert mode, the `sms:` URI of RFC 5724: `sms:<number>[,<number>...]`
  /// with an optional `?body=` percent-encoded. A URI holds no spaces, so they are
  /// left out of the numbers, and `#` would start a fragment, so it is encoded. With
  /// several numbers and Apple's form asked for, `sms://open?addresses=` instead; one
  /// number needs no such form, and keeps the one every phone reads.
  @override
  String buildQrString(Map<String, String> values) {
    final phone = (values['phone'] ?? '').trim();
    final message = values['message'] ?? '';
    if (values['form'] != smsUri) {
      return message.isEmpty ? 'SMSTO:$phone' : 'SMSTO:$phone:$message';
    }
    final numbers = [
      phone,
      for (final entry in QrEntries.read(values, _recipients)) entry['number']!,
    ].map(_uriNumber).where((n) => n.isNotEmpty).toList();
    final body = message.isEmpty ? '' : 'body=${Uri.encodeComponent(message)}';
    if (values['apple'] == 'true' && numbers.length > 1) {
      return '$_appleOpen${numbers.join(',')}${body.isEmpty ? '' : '&$body'}';
    }
    return 'sms:${numbers.join(',')}${body.isEmpty ? '' : '?$body'}';
  }

  static String _uriNumber(String number) =>
      number.replaceAll(RegExp(r'\s'), '').replaceAll('#', '%23');

  /// `SMSTO:`: the number runs to the first colon, the message is everything after
  /// it. `sms:`: the numbers run to the `?`, split at commas, and `body` is the
  /// message; any other query parameter is reported as unsupported.
  @override
  QrParsed? parse(String payload) {
    if (hasPrefixIgnoreCase(payload, 'SMSTO:')) {
      final rest = payload.substring(6);
      final colon = rest.indexOf(':');
      return QrParsed({
        'form': smsto,
        'phone': (colon < 0 ? rest : rest.substring(0, colon)).trim(),
        'recipients': '0',
        'apple': 'false',
        'message': colon < 0 ? '' : rest.substring(colon + 1),
      });
    }
    if (!hasPrefixIgnoreCase(payload, 'sms:')) return null;
    final rest = payload.substring(4);
    // Apple's form, with one slash or two: the numbers are a query parameter.
    final apple = RegExp(
      r'^/{1,2}open\?',
      caseSensitive: false,
    ).firstMatch(rest);
    final question = rest.indexOf('?');
    var numbers = apple != null
        ? <String>[]
        : (question < 0 ? rest : rest.substring(0, question))
              .split(',')
              .map(_decode)
              .toList();
    final unsupported = <String>[];
    var message = '';
    if (question >= 0) {
      for (final param in rest.substring(question + 1).split('&')) {
        if (param.isEmpty) continue;
        final equals = param.indexOf('=');
        final name = equals < 0 ? param : param.substring(0, equals);
        final value = equals < 0 ? '' : param.substring(equals + 1);
        if (name == 'body' && equals > 0 && message.isEmpty) {
          message = _decode(value);
        } else if (apple != null && name == 'addresses' && numbers.isEmpty) {
          numbers = value.split(',').map(_decode).toList();
        } else {
          addOnce(unsupported, name);
        }
      }
    }
    if (numbers.isEmpty) numbers = [''];
    return QrParsed({
      'form': smsUri,
      'apple': apple != null ? 'true' : 'false',
      'phone': numbers.first,
      'recipients': '${numbers.length - 1}',
      for (final (i, number) in numbers.skip(1).indexed)
        QrEntries.part('recipients', i, 'number'): number,
      'message': message,
    }, unsupported);
  }

  /// Percent-decoded, or as it is when it is not valid percent-encoding.
  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } on ArgumentError {
      return s;
    }
  }
}
