/// The in-app quick guide's content model. The text itself is generated
/// into guide_content.dart from tool/guide/content.js.
class QuickGuide {
  const QuickGuide({
    required this.title,
    required this.intro,
    required this.overview,
    required this.sections,
    required this.privacyTitle,
    required this.privacyImage,
    required this.privacyPoints,
    required this.tips,
    required this.closing,
  });

  final String title;
  final String intro;
  final List<GuideOverviewItem> overview;
  final List<GuideSection> sections;
  final String privacyTitle;
  final String privacyImage;
  final List<String> privacyPoints;
  final List<GuideTip> tips;
  final String closing;
}

class GuideOverviewItem {
  const GuideOverviewItem({
    required this.number,
    required this.title,
    required this.text,
  });

  final String number;
  final String title;
  final String text;
}

class GuideSection {
  const GuideSection({
    required this.number,
    required this.title,
    required this.blurb,
    required this.steps,
  });

  final String number;
  final String title;
  final String blurb;
  final List<GuideStep> steps;
}

class GuideStep {
  const GuideStep({
    required this.title,
    required this.images,
    required this.points,
  });

  final String title;

  /// Screenshot names in assets/guide, without the .jpg extension.
  final List<String> images;
  final List<String> points;
}

class GuideTip {
  const GuideTip({required this.title, required this.text});

  final String title;
  final String text;
}

/// The asset path of a guide screenshot.
String guideImageAsset(String name) => 'assets/guide/$name.jpg';
