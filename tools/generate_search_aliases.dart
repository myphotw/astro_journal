// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// search_aliases.json 생성: Messier M1~M110 + NGC/IC/Sh2 카탈로그 주요 대상.
void main() {
  final aliases = <String, List<String>>{};

  void add(String id, List<String> names) {
    if (names.isEmpty) return;
    aliases[id] = names;
  }

  // ── Messier M1 ~ M110 ─────────────────────────────────────────────────────
  const messier = <int, List<String>>{
    1: ['Crab Nebula', 'Crab'],
    2: [],
    3: [],
    4: [],
    5: [],
    6: ['Butterfly Cluster'],
    7: ['Ptolemy Cluster'],
    8: ['Lagoon Nebula', 'Lagoon'],
    9: [],
    10: [],
    11: ['Wild Duck Cluster'],
    12: [],
    13: ['Great Hercules Cluster', 'Hercules Globular', 'Great Globular Cluster'],
    14: [],
    15: [],
    16: ['Eagle Nebula', 'Pillars of Creation', 'Star Queen Nebula'],
    17: ['Omega Nebula', 'Swan Nebula', 'Horseshoe Nebula', 'Checkmark Nebula'],
    18: [],
    19: [],
    20: ['Trifid Nebula', 'Trifid'],
    21: [],
    22: ['Sagittarius Cluster'],
    23: [],
    24: ['Sagittarius Star Cloud', 'Delphinus Nebula'],
    25: [],
    26: [],
    27: ['Dumbbell Nebula', 'Dumbbell', 'Dumbbell Nebula', 'NGC 6853', 'NGC6853'],
    28: [],
    29: [],
    30: [],
    31: ['Andromeda Galaxy', 'Andromeda', 'NGC 224'],
    32: [],
    33: ['Triangulum Galaxy', 'Triangulum', 'Pinwheel Galaxy'],
    34: [],
    35: [],
    36: [],
    37: [],
    38: [],
    39: [],
    40: ['Winnecke 4'],
    41: [],
    42: ['Orion Nebula', 'Orion', 'Great Orion Nebula', 'NGC 1976'],
    43: ['De Mairan Nebula', 'M43'],
    44: ['Beehive Cluster', 'Praesepe', 'M44'],
    45: ['Pleiades', 'Seven Sisters', 'Subaru'],
    46: [],
    47: [],
    48: [],
    49: [],
    50: ['Heart-Shaped Cluster'],
    51: ['Whirlpool Galaxy', 'Whirlpool', 'NGC 5194'],
    52: [],
    53: [],
    54: [],
    55: [],
    56: [],
    57: ['Ring Nebula', 'Ring'],
    58: [],
    59: [],
    60: [],
    61: [],
    62: [],
    63: ['Sunflower Galaxy'],
    64: ['Black Eye Galaxy', 'Sleeping Beauty Galaxy'],
    65: [],
    66: [],
    67: [],
    68: [],
    69: [],
    70: [],
    71: [],
    72: [],
    73: [],
    74: ['Phantom Galaxy'],
    75: [],
    76: ['Little Dumbbell Nebula', 'Cork Nebula', 'Butterfly Nebula'],
    77: [],
    78: [],
    79: [],
    80: [],
    81: ['Bode Galaxy', "Bode's Galaxy", 'NGC 3031'],
    82: ['Cigar Galaxy', 'Cigar', 'NGC 3034'],
    83: ['Southern Pinwheel Galaxy', 'Southern Pinwheel'],
    84: [],
    85: [],
    86: [],
    87: ['Virgo A', 'Virgo A Galaxy'],
    88: [],
    89: [],
    90: [],
    91: [],
    92: [],
    93: [],
    94: [],
    95: [],
    96: [],
    97: ['Owl Nebula', 'Owl'],
    98: [],
    99: [],
    100: [],
    101: ['Pinwheel Galaxy', 'Pinwheel'],
    102: ['Spindle Galaxy', 'NGC 5866'],
    103: [],
    104: ['Sombrero Galaxy', 'Sombrero'],
    105: [],
    106: [],
    107: [],
    108: [],
    109: [],
    110: [],
  };

  for (final entry in messier.entries) {
    add('M${entry.key}', entry.value);
  }

  // ── NGC (assets/catalog/ngc.json) ─────────────────────────────────────────
  const ngc = <String, List<String>>{
    'NGC55': ['Sculptor Galaxy', 'Sculptor Bar Galaxy'],
    'NGC253': ['Sculptor Galaxy', 'Silver Coin Galaxy', 'Silver Dollar Galaxy'],
    'NGC300': ['Sculptor Pinwheel'],
    'NGC869': ['h Persei', 'h Persei Cluster', 'Double Cluster'],
    'NGC884': ['chi Persei', 'chi Persei Cluster', 'Double Cluster'],
    'NGC1232': ['Eridanus Spiral Galaxy'],
    'NGC1499': ['California Nebula', 'California'],
    'NGC1579': ['Northern Trifid Nebula', 'Trifid Nebula North'],
    'NGC2244': ['Rosette Cluster'],
    'NGC2264': ['Christmas Tree Cluster', 'Cone Nebula Cluster'],
    'NGC2392': ['Eskimo Nebula', 'Eskimo', 'Clownface Nebula'],
    'NGC2903': ['Leo Spiral Galaxy'],
    'NGC3372': ['Eta Carinae Nebula', 'Carina Nebula', 'Great Carina Nebula'],
    'NGC3628': ['Pancake Galaxy', 'Hamburger Galaxy'],
    'NGC4038': ['Antennae Galaxies', 'Antennae', 'Ringtail Galaxy'],
    'NGC4244': ['Calwell 26', 'Silver Needle Galaxy'],
    'NGC4565': ['Needle Galaxy', 'Needle'],
    'NGC4631': ['Whale Galaxy', 'Whale', 'Hockey Stick Galaxy'],
    'NGC5128': ['Centaurus A', 'Cen A'],
    'NGC5139': ['Omega Centauri', 'Omega Cen'],
    'NGC6188': ['Rim Nebula', 'Fighting Dragons of Ara'],
    'NGC6334': ['Cat Paw Nebula', 'Cat\'s Paw Nebula'],
    'NGC6357': ['War and Peace Nebula', 'Lobster Nebula'],
    'NGC6543': ['Cat Eye Nebula', 'Cat\'s Eye Nebula', 'Cat Eye'],
    'NGC6822': ['Barnard Galaxy', 'Barnard\'s Galaxy'],
    'NGC6992': ['Eastern Veil Nebula', 'Veil Nebula East', 'Network Nebula'],
    'NGC7000': ['North America Nebula', 'North America', 'NA Nebula'],
    'NGC7293': ['Helix Nebula', 'Helix', 'Eye of God'],
    'NGC7331': ['Deer Lick Group', 'Caldwell 30'],
    'NGC7789': ['Caroline\'s Rose', 'White Rose Cluster'],
  };
  ngc.forEach(add);

  // ── IC ────────────────────────────────────────────────────────────────────
  const ic = <String, List<String>>{
    'IC342': ['Hidden Galaxy'],
    'IC405': ['Flaming Star Nebula', 'Flaming Star'],
    'IC410': ['Tadpoles Nebula', 'Tadpoles'],
    'IC434': ['Horsehead Nebula', 'Horsehead', 'Barnard 33', 'B33'],
    'IC443': ['Jellyfish Nebula', 'Jellyfish'],
    'IC1318': ['Butterfly Nebula', 'Gamma Cygni Nebula'],
    'IC1396': ['Elephant Trunk Nebula', 'Elephant Trunk'],
    'IC1805': ['Heart Nebula', 'Heart'],
    'IC1848': ['Soul Nebula', 'Soul'],
    'IC2118': ['Witch Head Nebula', 'Witch Head'],
    'IC2177': ['Seagull Nebula', 'Seagull'],
    'IC4592': ['Blue Horsehead Nebula'],
    'IC4628': ['Prawn Nebula', 'Prawn'],
    'IC5067': ['Pelican Nebula', 'Pelican'],
    'IC5146': ['Cocoon Nebula', 'Cocoon'],
  };
  ic.forEach(add);

  // ── Sh2 ───────────────────────────────────────────────────────────────────
  const sh2 = <String, List<String>>{
    'Sh2-27': ['Rho Ophiuchi Nebula', 'Rho Ophiuchi'],
    'Sh2-29': [],
    'Sh2-40': [],
    'Sh2-54': [],
    'Sh2-101': ['Tulip Nebula', 'Tulip'],
    'Sh2-106': ['Celestial Snow Angel', 'Snow Angel Nebula'],
    'Sh2-132': ['Lion Nebula', 'Lion'],
    'Sh2-155': ['Cave Nebula', 'Cave'],
    'Sh2-157': ['Lobster Claw Nebula', 'Lobster Claw'],
    'Sh2-171': ['NGC 7822'],
    'Sh2-185': ['Cassiopeia Ghost', 'Ghost of Cassiopeia'],
    'Sh2-240': ['Spaghetti Nebula', 'Simeis 147'],
    'Sh2-264': ['Lambda Orionis Ring', 'Lambda Ori Ring'],
    'Sh2-276': ['Barnard Loop', 'Barnard\'s Loop'],
    'Sh2-308': ['Dolphin Nebula', 'Dolphin', 'Gourd Nebula'],
  };
  sh2.forEach(add);

  // ── Barnard / LDN (카탈로그 id 기준) ───────────────────────────────────────
  const barnard = <String, List<String>>{
    'B33': ['Horsehead Nebula', 'Horsehead', 'IC 434', 'IC434'],
    'B86': ['Ink Spot Nebula', 'Ink Spot'],
    'B142': ['Barnard E Nebula', 'Barnard\'s E'],
    'B143': ['Barnard E Nebula', 'Barnard\'s E'],
    'B68': ['Black Cloud', 'Black Cloud Nebula'],
    'B72': ['Snake Nebula', 'Snake'],
    'B103': ['Pipe Nebula', 'Pipe'],
    'B174': ['Snake Nebula'],
  };
  barnard.forEach(add);

  const ldn = <String, List<String>>{
    'LDN889': ['Pipe Nebula', 'Pipe'],
    'LDN1235': ['Polarissima Cluster Dark Nebula'],
    'LDN1622': ['Boogeyman Nebula', 'Boogeyman'],
    'LDN1773': ['Dark Wolf Nebula'],
    'LDN988': ['Dark Wolf Nebula'],
  };
  ldn.forEach(add);

  final out = File('assets/catalog/search_aliases.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(aliases),
  );
  print('Wrote ${aliases.length} alias entries to ${out.path}');
}
