// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Seestar 등록대상 천체목록.xlsx 기준 카탈로그 에셋 생성.
/// 실행: dart run tools/generate_seestar_catalog.dart
void main() {
  final projectRoot = Directory.current.path.endsWith('astro_journal')
      ? Directory.current
      : Directory('${Directory.current.path}/astro_journal');
  if (!File('${projectRoot.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from astro_journal project root.');
    exit(1);
  }

  final catalogDir = Directory('${projectRoot.path}/assets/catalog');
  final metadata = _loadExistingMetadata(catalogDir);
  final messierNgc = _buildMessierNgcMap();
  final caldwellPrimary = _loadCaldwellPrimaryMap(projectRoot);

  final raw = _seestarRawDesignations();
  _addAuthoritativePrimaryDesignations(raw, caldwellPrimary);
  final rawFile = File('${catalogDir.path}/seestar_raw.json');
  rawFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(raw));

  final groups = _buildEquivalenceGroups(
    raw,
    caldwellPrimary: caldwellPrimary,
    messierNgc: messierNgc,
    icDupToNgc: _loadOpenNgcIcDuplicates(),
  );

  final canonicalObjects = <Map<String, dynamic>>[];
  final idRemap = <String, String>{};
  final commonNames = <String, String>{};
  var aliasCount = 0;
  var commonNameCount = 0;
  var removedDuplicates = 0;

  for (final group in groups) {
    final canonicalId = group.canonicalId;
    final canonicalCatalog = group.canonicalCatalog;
    final canonicalNumber = group.canonicalNumber;
    final canonicalSuffix = group.canonicalSuffix;

    for (final member in group.members) {
      final memberId = _designationId(member);
      if (memberId != canonicalId) {
        idRemap[memberId] = canonicalId;
        removedDuplicates++;
      }
    }

    // Messier 대표: seestar_catalog row 생성 안 함 (alias만 Messier import 시 병합)
    if (canonicalCatalog == 'messier') {
      continue;
    }

    final meta = _resolveMetadata(
      canonicalId: canonicalId,
      catalog: canonicalCatalog,
      number: canonicalNumber,
      suffix: canonicalSuffix,
      members: group.members,
      metadata: metadata,
      caldwellPrimary: caldwellPrimary,
    );

    final aliases = <String>{};
    for (final member in group.members) {
      aliases.addAll(_aliasForms(member));
    }
    aliases.remove(canonicalId);
    aliases.remove(
      _displayLabel(canonicalCatalog, canonicalNumber, canonicalSuffix),
    );
    aliasCount += aliases.length;

    if (group.commonName != null && group.commonName!.isNotEmpty) {
      commonNames[canonicalId] = group.commonName!;
      commonNameCount++;
    } else if (meta.commonName != null && meta.commonName!.isNotEmpty) {
      commonNames[canonicalId] = meta.commonName!;
      commonNameCount++;
    }

    canonicalObjects.add({
      'id': canonicalId,
      'number': canonicalNumber,
      'catalog': canonicalCatalog,
      ...?(canonicalSuffix == null ? null : {'suffix': canonicalSuffix}),
      'displayName': _displayLabel(
        canonicalCatalog,
        canonicalNumber,
        canonicalSuffix,
      ),
      'commonName': group.commonName ?? meta.commonName ?? meta.name,
      'name': group.commonName ?? meta.commonName ?? meta.name,
      'objectType': meta.objectType,
      'type': meta.objectType,
      'constellation': meta.constellation,
      'ra': meta.ra,
      'dec': meta.dec,
      'magnitude': meta.magnitude,
      'seestarSupported': true,
      'aliases': _finalizeAliases(canonicalId, aliases.toList()),
    });
  }

  // Messier에 흡수된 designation은 seestar catalog row 생성 안 함 (idRemap만)
  final messierAbsorbed = idRemap.entries
      .where((e) => e.value.startsWith('M'))
      .length;

  final equivFile = File('${catalogDir.path}/catalog_equivalence.json');
  equivFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'groups': groups.map((g) => g.toJson()).toList(),
      'messierNgc': messierNgc.map((k, v) => MapEntry(k.toString(), v)),
      'idRemap': idRemap,
    }),
  );

  final commonFile = File('${catalogDir.path}/common_names.json');
  commonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(commonNames),
  );

  final seestarCatalogFile = File('${catalogDir.path}/seestar_catalog.json');
  seestarCatalogFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(canonicalObjects),
  );

  final remapFile = File('${catalogDir.path}/id_remap.json');
  remapFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(idRemap),
  );

  print('seestar_raw.json: ${raw.length} designations');
  print('seestar_catalog.json: ${canonicalObjects.length} canonical objects');
  print('Removed duplicate designations: $removedDuplicates');
  print('Messier-absorbed (no extra row): $messierAbsorbed');
  print('Total aliases: $aliasCount');
  print('Common names: $commonNameCount');
  print('id_remap entries: ${idRemap.length}');
}

// ── Excel parallel lists (등록대상 천체목록.xlsx) ───────────────────────────

List<Map<String, dynamic>> _seestarRawDesignations() {
  const ic = [
    '63',
    '342',
    '353',
    '360',
    '405',
    '410',
    '417',
    '430',
    '434',
    '443',
    '444',
    '447',
    '448',
    '1284',
    '1287',
    '1318',
    '1318A',
    '1318B',
    '1396',
    '1396A',
    '1396B',
    '1613',
    '1795',
    '1805',
    '1848',
    '1995',
    '2118',
    '2177',
    '2574',
    '2872',
    '2944',
    '4591',
    '4592',
    '4601',
    '4603',
    '4604',
    '4605',
    '4628',
    '4685',
    '4701',
    '4895',
    '5068',
    '5070',
    '5146',
  ];
  const ngc = [
    55,
    147,
    247,
    253,
    281,
    292,
    300,
    346,
    456,
    891,
    925,
    1269,
    1316,
    1365,
    1432,
    1435,
    1491,
    1499,
    1532,
    1579,
    1750,
    1966,
    1975,
    1990,
    2024,
    2052,
    2070,
    2077,
    2175,
    2237,
    2403,
    2678,
    2736,
    2903,
    3109,
    3199,
    3324,
    3372,
    3521,
    3576,
    3621,
    3628,
    4236,
    4244,
    4395,
    4437,
    4559,
    4565,
    4631,
    4656,
    4725,
    4945,
    5033,
    5128,
    5284,
    5907,
    6188,
    6334,
    6357,
    6729,
    6744,
    6888,
    6946,
    6960,
    6992,
    6995,
    7000,
    7023,
    7293,
    7331,
    7635,
    7640,
  ];
  const sh2 = [
    1,
    3,
    54,
    103,
    108,
    140,
    142,
    157,
    158,
    171,
    235,
    273,
    296,
    298,
    311,
  ];
  final caldwell = List.generate(109, (i) => i + 1);
  const rcw = [57, 77, 98, 100, 101, 114];
  const vdb = [31, 38, 106, 107, 123, 126, 136, 140, 141, 150, 152];

  final out = <Map<String, dynamic>>[];
  for (final n in ic) {
    final suffix = _icSuffix(n);
    out.add({
      'catalog': 'ic',
      'number': int.parse(n.replaceAll(RegExp(r'[AB]$'), '')),
      ...?(suffix == null ? null : {'suffix': suffix}),
    });
  }
  for (final n in ngc) {
    out.add({'catalog': 'ngc', 'number': n});
  }
  for (final n in sh2) {
    out.add({'catalog': 'sh2', 'number': n});
  }
  for (final n in caldwell) {
    out.add({'catalog': 'caldwell', 'number': n});
  }
  for (final n in rcw) {
    out.add({'catalog': 'rcw', 'number': n});
  }
  for (final n in vdb) {
    out.add({'catalog': 'vdb', 'number': n});
  }
  return out;
}

String? _icSuffix(String token) {
  if (token.endsWith('A')) return 'A';
  if (token.endsWith('B')) return 'B';
  return null;
}

// ── Equivalence ─────────────────────────────────────────────────────────────

class _Group {
  _Group({
    required this.canonicalId,
    required this.canonicalCatalog,
    required this.canonicalNumber,
    this.canonicalSuffix,
    required this.members,
    this.commonName,
  });

  final String canonicalId;
  final String canonicalCatalog;
  final int canonicalNumber;
  final String? canonicalSuffix;
  final List<Map<String, dynamic>> members;
  final String? commonName;

  Map<String, dynamic> toJson() => {
    'canonicalId': canonicalId,
    'members': members.map(_designationId).toList(),
    if (commonName != null) 'commonName': commonName,
  };
}

List<_Group> _buildEquivalenceGroups(
  List<Map<String, dynamic>> raw, {
  required Map<int, String> caldwellPrimary,
  required Map<int, int> messierNgc,
  required Map<String, String> icDupToNgc,
}) {
  const priority = ['messier', 'ngc', 'ic', 'caldwell', 'sh2', 'rcw', 'vdb'];
  const separateIc = {'1318A', '1318B', '1396A', '1396B'};

  final designationById = <String, Map<String, dynamic>>{};
  for (final d in raw) {
    designationById[_designationId(d)] = d;
  }

  final parent = <String, String>{};
  String find(String x) {
    parent[x] ??= x;
    if (parent[x] == x) return x;
    parent[x] = find(parent[x]!);
    return parent[x]!;
  }

  void unite(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  // Caldwell → primary NGC/IC/Sh2
  final ngcToIcDup = <String, String>{};
  for (final entry in icDupToNgc.entries) {
    ngcToIcDup[entry.value] = entry.key;
  }
  for (final entry in caldwellPrimary.entries) {
    final cId = 'C${entry.key}';
    if (!designationById.containsKey(cId)) continue;
    final primary = entry.value;
    if (designationById.containsKey(primary)) {
      unite(cId, primary);
      continue;
    }
    final icDup = ngcToIcDup[primary];
    if (icDup != null && designationById.containsKey(icDup)) {
      unite(cId, icDup);
    }
  }

  // OpenNGC IC duplicate → NGC (both in seestar list)
  for (final entry in icDupToNgc.entries) {
    final icId = entry.key;
    final ngcId = entry.value;
    if (designationById.containsKey(icId) &&
        designationById.containsKey(ngcId)) {
      unite(icId, ngcId);
    }
  }

  // Messier → NGC/IC in seestar list
  for (final entry in messierNgc.entries) {
    final ngcId = 'NGC${entry.key}';
    final mId = 'M${entry.value}';
    if (designationById.containsKey(ngcId)) {
      parent[mId] = mId;
      unite(ngcId, mId);
    }
  }

  // Known Sh2 ↔ Caldwell / Veil
  // Alias/common-name similarity is deliberately not an identity edge. All
  // cross-catalog unions above come from authoritative typed mappings only.

  // Force separate IC variants
  for (final token in separateIc) {
    final id = 'IC$token';
    if (designationById.containsKey(id)) {
      parent[id] = id;
    }
  }

  final clusters = <String, List<Map<String, dynamic>>>{};
  for (final id in designationById.keys) {
    if (separateIc.any((s) => id == 'IC$s')) {
      clusters[id] = [designationById[id]!];
      continue;
    }
    final root = find(id);
    clusters.putIfAbsent(root, () => []).add(designationById[id]!);
  }

  final groups = <_Group>[];
  for (final members in clusters.values) {
    final canonical = _pickCanonical(members, priority, messierNgc);
    groups.add(
      _Group(
        canonicalId: canonical.id,
        canonicalCatalog: canonical.catalog,
        canonicalNumber: canonical.number,
        canonicalSuffix: canonical.suffix,
        members: members,
        commonName: _commonNameForGroup(members, caldwellPrimary),
      ),
    );
  }
  groups.sort((a, b) => a.canonicalId.compareTo(b.canonicalId));
  return groups;
}

class _CanonicalPick {
  _CanonicalPick(this.id, this.catalog, this.number, this.suffix);
  final String id;
  final String catalog;
  final int number;
  final String? suffix;
}

_CanonicalPick _pickCanonical(
  List<Map<String, dynamic>> members,
  List<String> priority,
  Map<int, int> messierNgc,
) {
  // Messier absorption: if any member NGC maps to Messier, use Messier
  for (final m in members) {
    if (m['catalog'] == 'ngc') {
      final num = m['number'] as int;
      if (messierNgc.containsKey(num)) {
        final messierNum = messierNgc[num]!;
        return _CanonicalPick('M$messierNum', 'messier', messierNum, null);
      }
    }
  }

  for (final cat in priority) {
    if (cat == 'messier') continue;
    for (final m in members) {
      if (m['catalog'] == cat) {
        final suffix = m['suffix'] as String?;
        return _CanonicalPick(
          _designationId(m),
          cat,
          m['number'] as int,
          suffix,
        );
      }
    }
  }
  final first = members.first;
  return _CanonicalPick(
    _designationId(first),
    first['catalog'] as String,
    first['number'] as int,
    first['suffix'] as String?,
  );
}

String? _commonNameForGroup(
  List<Map<String, dynamic>> members,
  Map<int, String> caldwellPrimary,
) {
  const names = {
    'IC1805': '하트 성운',
    'IC1848': '영혼 성운',
    'NGC7000': '북아메리카 성운',
    'IC434': '말머리 성운',
    'NGC6960': '서쪽 베일 성운',
    'NGC6992': '동쪽 베일 성운',
    'NGC6995': '베일 성운',
    'NGC2237': '장미 성운',
    'NGC2244': '장미 성단',
    'NGC1579': '북쪽 삼렬 성운',
    'NGC3372': '에타 카리나 성운',
    'NGC7293': '쌍가락지 성운',
    'IC1318A': '나비 성운 A',
    'IC1318B': '나비 성운 B',
    'IC1396A': '코끼리 코 성운 A',
    'IC1396B': '코끼리 코 성운 B',
    'Sh2-155': '동굴 성운',
    'IC342': '숨겨진 은하',
    'NGC4565': '바늘 은하',
    'NGC6543': '고양이눈 성운',
    'NGC2392': '에스키모 성운',
    'NGC6822': '바너드 은하',
    'NGC5139': '오메가 센타우리',
    'NGC7023': '붓꽃 성운',
    'NGC1499': '캘리포니아 성운',
    'NGC6334': '고양이 발 성운',
    'NGC6357': '전쟁과 평화 성운',
    'IC405': '불꽃별 성운',
    'IC410': '올챙이 성운',
    'IC443': '해파리 성운',
    'IC1396': '코끼리 코 성운',
    'IC5067': '펠리칸 성운',
    'IC5146': '고치 성운',
    'Sh2-101': '튤립 성운',
    'Sh2-308': '돌고래 성운',
    'NGC2175': '원숭이 머리 성운',
    'Sh2-273': '크리스마스 트리 성운',
    'Sh2-3': 'Green Ring 성운',
    'Sh2-54': 'Nest 성운',
    'Sh2-296': "Seagull's Wings",
    'Sh2-311': 'Skull and Crossbone 성운',
  };
  for (final m in members) {
    final id = _designationId(m);
    if (names.containsKey(id)) return names[id];
  }
  for (final m in members) {
    if (m['catalog'] == 'caldwell') {
      final primary = caldwellPrimary[m['number'] as int];
      if (primary != null && names.containsKey(primary)) {
        return names[primary];
      }
    }
  }
  return null;
}

String _designationId(Map<String, dynamic> d) {
  final catalog = d['catalog'] as String;
  final number = d['number'] as int;
  final suffix = d['suffix'] as String?;
  switch (catalog) {
    case 'messier':
      return 'M$number';
    case 'ngc':
      return 'NGC$number';
    case 'ic':
      return 'IC$number${suffix ?? ''}';
    case 'caldwell':
      return 'C$number';
    case 'sh2':
      return 'Sh2-$number';
    case 'rcw':
      return 'RCW$number';
    case 'vdb':
      return 'vdB$number';
    default:
      return '$catalog$number';
  }
}

String _displayLabel(String catalog, int number, String? suffix) {
  switch (catalog) {
    case 'messier':
      return 'M$number';
    case 'ngc':
      return 'NGC $number';
    case 'ic':
      return 'IC $number${suffix ?? ''}';
    case 'caldwell':
      return 'Caldwell $number';
    case 'sh2':
      return 'Sh2-$number';
    case 'rcw':
      return 'RCW $number';
    case 'vdb':
      return 'vdB $number';
    default:
      return '$catalog $number';
  }
}

List<String> _aliasForms(Map<String, dynamic> d) {
  final id = _designationId(d);
  final catalog = d['catalog'] as String;
  final number = d['number'] as int;
  final suffix = d['suffix'] as String?;
  final forms = <String>{id, _displayLabel(catalog, number, suffix)};
  if (catalog == 'ngc') {
    forms.add('NGC $number');
    forms.add('NGC$number');
  } else if (catalog == 'ic') {
    forms.add('IC $number${suffix ?? ''}');
    forms.add('IC$number${suffix ?? ''}');
  } else if (catalog == 'caldwell') {
    forms.add('Caldwell $number');
    forms.add('C$number');
    forms.add('Caldwell$number');
  } else if (catalog == 'sh2') {
    forms.add('Sh2 $number');
    forms.add('SH2$number');
    forms.add('Sh2-$number');
  } else if (catalog == 'rcw') {
    forms.add('RCW$number');
  } else if (catalog == 'vdb') {
    forms.add('vdB $number');
    forms.add('VDB$number');
    forms.add('vdB$number');
  }
  return forms.toList();
}

List<String> _finalizeAliases(String canonicalId, List<String> aliases) {
  final set = aliases.toSet()..remove(canonicalId);
  const extra = {
    'NGC6960': ['베일', 'Veil Nebula', 'Veil', 'Western Veil'],
    'NGC6992': ['베일', 'Veil Nebula', 'Veil', 'Eastern Veil'],
    'NGC6995': ['베일', 'Veil Nebula', 'Veil'],
    'IC434': ['말머리', 'Horsehead Nebula', 'Horsehead'],
    'IC1805': ['하트', 'Heart Nebula', 'Heart'],
    'IC1848': ['영혼', 'Soul Nebula', 'Soul'],
    'NGC7000': ['북아메리카', 'North America Nebula', 'C20', 'Caldwell 20'],
  };
  if (extra.containsKey(canonicalId)) {
    set.addAll(extra[canonicalId]!);
  }
  return set.toList()..sort();
}

Map<int, int> _buildMessierNgcMap() {
  // Messier alias에 포함된 NGC → Messier 번호
  const pairs = {
    224: 31,
    598: 33,
    1952: 1,
    1976: 42,
    2024: 42, // M43 region - keep M42
    3031: 81,
    3034: 82,
    4594: 104,
    5194: 51,
    5272: 3,
    6205: 13,
    6218: 12,
    6254: 10,
    6405: 6,
    6523: 8,
    6611: 16,
    6656: 22,
    6720: 57,
    6853: 27,
    7078: 15,
    7089: 2,
    7099: 30,
    7654: 52,
    7789: 37,
    869: 34, // double cluster partial
    884: 34,
  };
  return pairs;
}

Map<int, String> _loadCaldwellPrimaryMap(Directory projectRoot) {
  final file = File(
    '${projectRoot.path}/tools/catalog_data/caldwell_identity.json',
  );
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final raw = root['mapping'] as Map<String, dynamic>?;
  if (raw == null || raw.length != 109) {
    throw StateError('Caldwell identity mapping must contain C1-C109.');
  }

  final result = <int, String>{};
  for (var number = 1; number <= 109; number++) {
    final value = raw['$number'] as String?;
    if (value == null || value.trim().isEmpty) {
      throw StateError('Missing Caldwell identity mapping: C$number');
    }
    result[number] = value.trim();
  }
  return result;
}

void _addAuthoritativePrimaryDesignations(
  List<Map<String, dynamic>> raw,
  Map<int, String> caldwellPrimary,
) {
  final known = raw.map(_designationId).toSet();
  for (final primaryId in caldwellPrimary.values) {
    if (known.contains(primaryId)) continue;
    final designation = _designationFromTypedId(primaryId);
    if (designation == null) continue;
    raw.add(designation);
    known.add(primaryId);
  }
}

Map<String, dynamic>? _designationFromTypedId(String id) {
  final match = RegExp(r'^(NGC|IC)(\d+)([AB])?$').firstMatch(id);
  if (match != null) {
    return {
      'catalog': match.group(1) == 'NGC' ? 'ngc' : 'ic',
      'number': int.parse(match.group(2)!),
      if (match.group(3) != null) 'suffix': match.group(3),
    };
  }
  final sh2 = RegExp(r'^Sh2-(\d+)$').firstMatch(id);
  if (sh2 != null) {
    return {'catalog': 'sh2', 'number': int.parse(sh2.group(1)!)};
  }
  return null;
}

class _Meta {
  _Meta({
    required this.name,
    this.commonName,
    required this.objectType,
    required this.constellation,
    required this.ra,
    required this.dec,
    required this.magnitude,
  });
  final String name;
  final String? commonName;
  final String objectType;
  final String constellation;
  final String ra;
  final String dec;
  final String magnitude;
}

_Meta _resolveMetadata({
  required String canonicalId,
  required String catalog,
  required int number,
  String? suffix,
  required List<Map<String, dynamic>> members,
  required Map<String, _Meta> metadata,
  required Map<int, String> caldwellPrimary,
}) {
  if (metadata.containsKey(canonicalId)) return metadata[canonicalId]!;

  for (final m in members) {
    final id = _designationId(m);
    if (metadata.containsKey(id)) return metadata[id]!;
  }

  for (final m in members) {
    if (m['catalog'] == 'caldwell') {
      final primary = caldwellPrimary[m['number'] as int];
      if (primary != null && metadata.containsKey(primary)) {
        return metadata[primary]!;
      }
    }
  }

  final label = _displayLabel(catalog, number, suffix);
  return _Meta(
    name: label,
    objectType: _defaultObjectType(catalog, number),
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-',
  );
}

String _defaultObjectType(String catalog, int number) {
  if (catalog == 'caldwell' &&
      {2, 6, 15, 39, 41, 59, 69, 70, 75, 79, 90}.contains(number)) {
    return '행성상성운';
  }
  if (catalog == 'caldwell' && {13, 16, 33, 48, 94, 96, 97}.contains(number)) {
    return '산개성단';
  }
  if (catalog == 'caldwell' && {80, 86, 93, 103}.contains(number)) {
    return '구상성단';
  }
  switch (catalog) {
    case 'ngc':
    case 'ic':
    case 'sh2':
    case 'rcw':
    case 'vdb':
      return '발광성운';
    case 'caldwell':
      return '은하';
    default:
      return '기타';
  }
}

Map<String, _Meta> _loadExistingMetadata(Directory catalogDir) {
  final map = <String, _Meta>{};
  const files = {
    'messier.json': 'messier',
    'ngc.json': 'ngc',
    'ic.json': 'ic',
    'caldwell.json': 'caldwell',
    'sh2.json': 'sh2',
  };
  for (final entry in files.entries) {
    final file = File('${catalogDir.path}/${entry.key}');
    if (!file.existsSync()) continue;
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final id = m['id'] as String;
      map[id] = _Meta(
        name: m['name'] as String,
        commonName: m['name'] as String,
        objectType: _normalizeObjectType(m['type'] as String),
        constellation: m['constellation'] as String,
        ra: m['ra'] as String,
        dec: m['dec'] as String,
        magnitude: m['magnitude'] as String,
      );
    }
  }
  return map;
}

String _normalizeObjectType(String legacy) {
  if (legacy.contains('행성상')) return '행성상성운';
  if (legacy.contains('구상')) return '구상성단';
  if (legacy.contains('산개')) return '산개성단';
  if (legacy == '은하') return '은하';
  if (legacy.contains('성운') || legacy.contains('성단')) return '발광성운';
  if (legacy.contains('행성')) return '기타';
  if (legacy.contains('항성') || legacy.contains('위성')) return '기타';
  return legacy;
}

Map<String, String> _loadOpenNgcIcDuplicates() {
  final file = File('${Directory.current.path}/tools/openngc/NGC.csv');
  if (!file.existsSync()) return {};
  final map = <String, String>{};
  final ngcRef = RegExp(r'^0*(\d+)([A-Z]?)$');
  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('IC')) continue;
    final parts = line.split(';');
    if (parts.length < 2 || parts[1] != 'Dup') continue;
    final icToken = parts[0];
    final icNum = icToken
        .replaceFirst('IC', '')
        .replaceFirst(RegExp(r'^0+'), '');
    final icId = 'IC${icNum.isEmpty ? '0' : icNum}';
    String? ngcNumber;
    for (var i = parts.length - 1; i >= 0; i--) {
      final field = parts[i].trim();
      final match = ngcRef.firstMatch(field);
      if (match != null && int.parse(match.group(1)!) < 10000) {
        ngcNumber = match.group(1);
        break;
      }
    }
    if (ngcNumber != null) {
      map[icId] = 'NGC$ngcNumber';
    }
  }
  return map;
}
