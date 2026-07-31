import 'target.dart';

/// Eine konkrete Ausführung: ein Satz, ein Durchgang, ein Block.
///
/// "3 Sätze à 12 Wiederholungen mit 20 kg" sind drei SetSpecs.
/// "10 Minuten Tonleitern bei 60 bpm" ist einer.
class SetSpec {
  const SetSpec({required this.target, this.load, this.note});

  final Target target;
  final Load? load;
  final String? note;

  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    if (load != null) 'load': load!.toJson(),
    if (note != null) 'note': note,
  };

  static SetSpec fromJson(Map<String, dynamic> json) => SetSpec(
    target: Target.fromJson(json['target'] as Map<String, dynamic>),
    load: json['load'] == null
        ? null
        : Load.fromJson(json['load'] as Map<String, dynamic>),
    note: json['note'] as String?,
  );

  SetSpec copyWith({Target? target, Load? load, String? note}) => SetSpec(
    target: target ?? this.target,
    load: load ?? this.load,
    note: note ?? this.note,
  );

  /// "12 Wdh. · 20 kg"
  String describe() {
    final parts = <String>[target.describe()];
    if (load != null) parts.add(load!.describe());
    return parts.join(' · ');
  }
}
