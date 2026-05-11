/// Curated pool of moments a parent can log against each hero.
///
/// The first 6 entries per hero are the "top picks" shown by default in
/// the parent-log sheet. The rest reveal when the parent taps
/// "See more moments". A parent can also write their own custom moment.
class HeroMomentPool {
  static const Map<String, List<String>> topPicks = {
    'rafi': [
      'Tried the slide they used to skip',
      'Joined a workshop on their own',
      'Asked a question to a grown-up they didn\'t know',
      'Went first when nobody else would',
      'Tried a food they were afraid of',
      'Spoke up when something felt unfair',
    ],
    'ellie': [
      'Shared their snack with a friend',
      'Included a kid who was playing alone',
      'Cheered when a friend won',
      'Said sorry without being asked',
      'Helped a younger kid who fell',
      'Made a card or drawing for someone',
    ],
    'gerry': [
      'Tried a workshop they\'d never done',
      'Asked "why?" or "how?" three times in a day',
      'Tasted a new flavor or ingredient',
      'Read a book on their own',
      'Explored a new corner of the venue',
      'Followed up on something they were curious about',
    ],
    'zena': [
      'Made art at a workshop',
      'Built their own FIT meal combo',
      'Told a story at a reflection moment',
      'Invented a new game with friends',
      'Drew or painted something at home',
      'Made up a character and played them',
    ],
  };

  static const Map<String, List<String>> extras = {
    'rafi': [
      'Climbed higher than last visit',
      'Performed on stage at an event',
      'Stayed at a workshop without their parent',
      'Tried a new sport for the first time',
      'Went on the spiral slide / zipline',
      'Took a risk and it didn\'t work — and tried again',
    ],
    'ellie': [
      'Said thank you to staff without a prompt',
      'Let another kid go first',
      'Comforted a crying child',
      'Brought water or food for mom or dad',
      'Donated an old toy',
      'Listened when a friend was upset',
    ],
    'gerry': [
      'Asked what an unfamiliar word means',
      'Watched staff prepare food and asked about it',
      'Compared two foods and noticed a difference',
      'Tried a food from a different culture',
      'Picked a workshop based on something they read',
      'Researched something at home and told us about it',
    ],
    'zena': [
      'Decorated their birthday party themselves',
      'Wrote or dictated a story or poem',
      'Mixed ingredients to invent a flavor',
      'Made a gift for someone',
      'Photographed something they made',
      'Sang, danced, or acted at an event',
    ],
  };

  /// Top 6 + extras combined, in display order.
  static List<String> allFor(String hero) => [
        ...?topPicks[hero],
        ...?extras[hero],
      ];
}
