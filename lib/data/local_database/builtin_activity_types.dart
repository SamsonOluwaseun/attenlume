/// Built-in activity types (NFR-03) [P0-09].
///
/// IDs are fixed UUID v4 values so every install, fixture and re-imported
/// export agrees on them. Never change an ID or key once released.
class BuiltinActivityType {
  const BuiltinActivityType(this.id, this.key, this.label, this.icon);

  final String id;
  final String key;
  final String label;

  /// Lucide icon name.
  final String icon;
}

const builtinActivityTypes = <BuiltinActivityType>[
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000001',
    'session',
    'Session',
    'presentation',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000002',
    'keynote',
    'Keynote',
    'mic',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000003',
    'panel',
    'Panel',
    'users',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000004',
    'breakout',
    'Breakout',
    'messages-square',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000005',
    'workshop',
    'Workshop',
    'hammer',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000006',
    'exhibit',
    'Exhibit',
    'store',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000007',
    'business_conversation',
    'Conversation',
    'handshake',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000008',
    'networking',
    'Networking',
    'contact',
  ),
  BuiltinActivityType(
    '00000000-0000-4000-8000-000000000009',
    'personal_reflection',
    'Reflection',
    'lightbulb',
  ),
];

/// Types that need the "Does the other person know?" check (FR-ACT-07).
const consentCheckTypeKeys = {'business_conversation', 'networking'};
