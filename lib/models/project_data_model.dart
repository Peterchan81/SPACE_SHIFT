class ProjectDataModel {
  String projectInfo;
  String sourceType;
  dynamic sourceData;
  dynamic recognitionData;
  dynamic userCorrections;
  dynamic cadData;
  dynamic isoData;
  dynamic renderData;
  List<dynamic> history;
  String currentStage;
  String saveState;

  ProjectDataModel({
    required this.projectInfo,
    required this.sourceType,
    this.sourceData,
    this.recognitionData,
    this.userCorrections,
    this.cadData,
    this.isoData,
    this.renderData,
    required this.history,
    required this.currentStage,
    required this.saveState,
  });
}