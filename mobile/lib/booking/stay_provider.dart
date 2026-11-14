import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';

/// The stay the customer is looking for: which nights and how many guests.
class Stay {
  static const maxNights = 30;
  static const maxGuests = 6;

  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;

  const Stay({
    required this.checkIn,
    required this.checkOut,
    required this.guests,
  });

  int get nights => checkOut.difference(checkIn).inDays;

  String get checkInText => isoDate(checkIn);
  String get checkOutText => isoDate(checkOut);

  Stay copyWith({DateTime? checkIn, DateTime? checkOut, int? guests}) => Stay(
    checkIn: checkIn ?? this.checkIn,
    checkOut: checkOut ?? this.checkOut,
    guests: guests ?? this.guests,
  );
}

class StayNotifier extends Notifier<Stay> {
  @override
  Stay build() {
    final today = dateOnly(DateTime.now());
    return Stay(
      checkIn: today,
      checkOut: today.add(const Duration(days: 1)),
      guests: 1,
    );
  }

  /// Returns an error text when the dates cannot be used, otherwise null.
  String? setDates(DateTime checkIn, DateTime checkOut) {
    final inDay = dateOnly(checkIn);
    var outDay = dateOnly(checkOut);

    // Picking one single day means one night.
    if (!outDay.isAfter(inDay)) outDay = inDay.add(const Duration(days: 1));

    if (outDay.difference(inDay).inDays > Stay.maxNights) {
      return 'You can stay up to ${Stay.maxNights} nights in one booking.';
    }

    state = state.copyWith(checkIn: inDay, checkOut: outDay);
    return null;
  }

  /// If the saved check-in day has passed (the app stayed open overnight),
  /// move the same number of nights to start today.
  void refreshIfStale() {
    final today = dateOnly(DateTime.now());
    if (!state.checkIn.isBefore(today)) return;
    state = state.copyWith(
      checkIn: today,
      checkOut: today.add(Duration(days: state.nights)),
    );
  }

  void setGuests(int guests) {
    state = state.copyWith(guests: guests.clamp(1, Stay.maxGuests));
  }
}

final stayProvider = NotifierProvider<StayNotifier, Stay>(StayNotifier.new);
