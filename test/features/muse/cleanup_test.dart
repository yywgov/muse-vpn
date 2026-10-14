// 穿云 1.1.1 - unit tests for the stability cut: subscriptions can no longer override the
// app's config (WARP / Psiphon chain, direct DNS, test URL, TLS fragment), and rules saved
// with the removed 「直连并分片」 outbound become 直连.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

Map<String, dynamic> _override({Map<String, dynamic>? headers, UserOverride? userOverride}) =>
    jsonDecode(ProfileParser.profileOverride(populatedHeaders: headers, userOverride: userOverride))
        as Map<String, dynamic>;

Map<String, dynamic> _populate(Map<String, dynamic> remoteHeaders) =>
    ProfileParser.populateHeaders(content: '', remoteHeaders: remoteHeaders).getOrElse((_) => <String, dynamic>{});

void main() {
  group('profileOverride', () {
    test('extra-security header no longer chains through WARP / Psiphon', () {
      for (final mode in ['warp', 'psiphon']) {
        expect(_override(headers: {'extra-security': mode}), isEmpty);
      }
    });

    test('stored chain / DNS / test-url / fragment overrides are ignored', () {
      final o = _override(
        headers: {
          'chain-status': 'extra_security',
          'extra-security': {'mode': 'warp'},
          'direct-dns-address': 'udp://8.8.8.8',
          'remote-dns-address': 'udp://1.1.1.1',
          'connection-test-url': 'http://example.com',
          'tls-tricks': {'enable-fragment': true},
          'fragment': '2-4,10-20,tlshello',
        },
      );
      expect(o, isEmpty);
    });

    test('an old UserOverride with extraSecurity / enableFragment is ignored', () {
      expect(_override(userOverride: const UserOverride(extraSecurity: 'warp', enableFragment: true)), isEmpty);
    });

    test('applyProfileOverride with the empty override keeps the options as they are', () {
      final options = {'direct-dns-address': 'udp://223.5.5.5', 'chain-status': 'off'};
      expect(ProfileParser.applyProfileOverride(Map.of(options), ProfileParser.profileOverride(populatedHeaders: {'extra-security': 'warp'}, userOverride: null)), equals(options));
    });
  });

  group('populateHeaders', () {
    test('option overrides are dropped', () {
      final h = _populate({
        'extra-security': 'warp',
        'fragment': '2-4,10-20,tlshello',
        'direct-dns-address': 'udp://8.8.8.8',
        'connection-test-url': 'http://example.com',
      });
      expect(h, isEmpty);
    });

    test('title, traffic info and update interval are kept', () {
      final h = _populate({
        'profile-title': 'name',
        'subscription-userinfo': 'upload=0; download=1; total=2; expire=0',
        'profile-update-interval': '12',
      });
      expect(h.keys, containsAll(['profile-title', 'subscription-userinfo', 'profile-update-interval']));
    });
  });

  group('migrateFragmentOutbound', () {
    test('「直连并分片」 becomes 直连, other outbounds stay', () {
      final rules = [
        Rule(name: 'a', outbound: Outbound.direct_with_fragment),
        Rule(name: 'b', outbound: Outbound.proxy),
        Rule(name: 'c', outbound: Outbound.block),
      ];
      expect(migrateFragmentOutbound(rules), isTrue);
      expect(rules.map((r) => r.outbound), [Outbound.direct, Outbound.proxy, Outbound.block]);
    });

    test('nothing to migrate', () {
      expect(migrateFragmentOutbound([Rule(name: 'a', outbound: Outbound.direct)]), isFalse);
    });
  });
}
