/// 현장미팅 문의에 입력된 최소 정보.
class SiteMeetingRequest {
  const SiteMeetingRequest({
    required this.name,
    required this.contact,
    required this.visitArea,
    required this.preferredDateTime,
    required this.notes,
    required this.privacyAgreed,
  });

  final String name;
  final String contact;
  final String visitArea;
  final String preferredDateTime;
  final String notes;
  final bool privacyAgreed;
}
