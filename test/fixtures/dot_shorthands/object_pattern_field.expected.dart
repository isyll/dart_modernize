enum Priority { low, high }

sealed class Task {}

class Job extends Task {
  Job(this.priority);

  final Priority priority;
}

class Chore extends Task {}

String label(Task task) => switch (task) {
  Job(priority: .high) => 'urgent',
  Job() => 'job',
  Chore() => 'chore',
};
