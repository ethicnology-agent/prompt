class OpenCodeSession {
  const OpenCodeSession({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.branch,
    this.changedFiles,
    this.additions,
    this.deletions,
    this.shareUrl,
    this.modelProviderId,
    this.modelId,
    this.agentName,
  });

  final String id;
  final String projectId;
  final String directory;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentId;
  final String? branch;
  final int? changedFiles;
  final int? additions;
  final int? deletions;
  final String? shareUrl;
  final String? modelProviderId;
  final String? modelId;
  final String? agentName;

  OpenCodeSession withTitle(String title) => OpenCodeSession(
    id: id,
    projectId: projectId,
    directory: directory,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    parentId: parentId,
    branch: branch,
    changedFiles: changedFiles,
    additions: additions,
    deletions: deletions,
    shareUrl: shareUrl,
    modelProviderId: modelProviderId,
    modelId: modelId,
    agentName: agentName,
  );
}
