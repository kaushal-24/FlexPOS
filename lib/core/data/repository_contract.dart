import 'package:supabase_flutter/supabase_flutter.dart';

/// Stable substitution boundary for data repositories.
///
/// Feature repositories deliberately expose their typed domain methods while
/// sharing this small contract so providers and tests can replace the network
/// implementation without depending on a concrete repository class.
abstract interface class SupabaseRepositoryContract {
  SupabaseClient get client;
}
