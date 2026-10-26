/// The round types shared by the bundle contracts (docs/design/scripting.md
/// §4.3).
///
/// The type of a round is set by the host, never by a script. It is the
/// `type` of a round and of a schedule entry in the `follow_up` input, and
/// the optional `trigger.type` of the `question_selection` input.
library;

/// A scheduled round: the scheduling script placed it in the schedule.
const String roundTypeBeep = 'beep';

/// A round a `follow_up` script scheduled after an answered round.
const String roundTypeFollowUp = 'follow_up';

/// A round the participant started on their own (a self check-in). The host
/// also tags it `participant`.
const String roundTypeParticipant = 'participant';

/// The round types, in the order the contracts list them: [roundTypeBeep],
/// [roundTypeFollowUp] and [roundTypeParticipant]. A follow-up round and a
/// participant round can themselves be followed up.
const List<String> roundTypes = [
  roundTypeBeep,
  roundTypeFollowUp,
  roundTypeParticipant,
];
