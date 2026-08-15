/// 무료 예상견적 요청에 필요한 최소 입력값.
class EstimateRequest {
  const EstimateRequest({
    required this.spaceType,
    required this.approximateArea,
    required this.constructionScope,
    required this.desiredColorTone,
    required this.customColorTone,
    required this.notes,
  });

  final String spaceType;
  final String approximateArea;
  final String constructionScope;
  final String desiredColorTone;
  final String customColorTone;
  final String notes;
}
