part of 'sumi_store.dart';

class TodoController extends ChangeNotifier {
  final List<TodoItem> _items = [];
  DateTime _selectedDate = dateOnly(DateTime.now());

  List<TodoItem> get items => UnmodifiableListView(_items);
  DateTime get selectedDate => _selectedDate;

  void markChanged() => notifyListeners();
}

class ProjectController extends ChangeNotifier {
  final List<Project> _projects = [];
  final List<MonthCard> _monthCards = [];
  String? _currentProjectId;

  List<Project> get projects => UnmodifiableListView(_projects);
  List<MonthCard> get monthCards => UnmodifiableListView(_monthCards);
  String? get currentProjectId => _currentProjectId;

  void markChanged() => notifyListeners();
}

class MilestoneController extends ChangeNotifier {
  void markChanged() => notifyListeners();
}

class DailyReflectionController extends ChangeNotifier {
  int revision = 0;

  void markChanged() {
    revision++;
    notifyListeners();
  }
}

enum TodoComposeResult { accepted, empty, busy }

enum FutureTodoComposeStage {
  idle,
  generating,
  awaitingConfirmation,
  completed,
  cancelled,
}

class FutureTodoComposeState {
  final FutureTodoComposeStage stage;
  final String? requestId;
  final String? targetDate;
  final String originalInput;
  final List<String> candidates;

  const FutureTodoComposeState({
    this.stage = FutureTodoComposeStage.idle,
    this.requestId,
    this.targetDate,
    this.originalInput = '',
    this.candidates = const [],
  });

  bool get isBusy =>
      stage == FutureTodoComposeStage.generating ||
      stage == FutureTodoComposeStage.awaitingConfirmation;
  bool get canCancel => isBusy;
}

class FutureTodoController {
  final ValueNotifier<FutureTodoComposeState> state = ValueNotifier(
    const FutureTodoComposeState(),
  );

  void dispose() => state.dispose();
}

class SettingsController extends ChangeNotifier {
  AppSettings _value = const AppSettings();

  AppSettings get value => _value;

  void markChanged() => notifyListeners();
}

class ChatViewState {
  final String? conversationId;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final bool isLoadingConversation;
  final bool isTemporaryConversation;
  final String? activityLabel;
  final int messageSentSequence;
  final ChatFailure? failure;
  final Set<String> milestoneSourceMessageIds;
  final Set<String> memorySourceMessageIds;
  final ChatMessage? pendingUserMessage;

  const ChatViewState({
    required this.conversationId,
    required this.messages,
    required this.isStreaming,
    required this.isLoadingConversation,
    required this.isTemporaryConversation,
    required this.activityLabel,
    required this.messageSentSequence,
    required this.failure,
    this.milestoneSourceMessageIds = const {},
    this.memorySourceMessageIds = const {},
    this.pendingUserMessage,
  });

  static const empty = ChatViewState(
    conversationId: null,
    messages: [],
    isStreaming: false,
    isLoadingConversation: false,
    isTemporaryConversation: false,
    activityLabel: null,
    messageSentSequence: 0,
    failure: null,
    milestoneSourceMessageIds: {},
    memorySourceMessageIds: {},
    pendingUserMessage: null,
  );
}

class ChatFailure {
  final String userMessageId;
  final String message;
  final bool retryable;

  const ChatFailure({
    required this.userMessageId,
    required this.message,
    required this.retryable,
  });
}

class ChatController {
  final ValueNotifier<ChatViewState> view = ValueNotifier(ChatViewState.empty);

  void dispose() => view.dispose();
}

class SelectionController extends ChangeNotifier {
  int navigateToTodaySequence = 0;

  void markChanged() => notifyListeners();
}
