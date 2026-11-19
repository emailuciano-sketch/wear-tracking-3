import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/formatters.dart';
import 'stops_report_screen.dart';
import 'trips_report_screen.dart';

enum _PeriodOption { today, yesterday, custom }

enum _ReportKind { trips, stops }

class _ReportSelection {
  final _ReportKind kind;
  final String startIso;
  final String endIso;

  const _ReportSelection({
    required this.kind,
    required this.startIso,
    required this.endIso,
  });
}

Future<void> showReportConfigureDialog(
  BuildContext context, {
  required int deviceId,
  required String deviceName,
}) async {
  var period = _PeriodOption.today;
  var reportKind = _ReportKind.trips;

  final now = DateTime.now();
  var customStart = DateTime(now.year, now.month, now.day, 0, 0);
  var customEnd = customStart.add(const Duration(days: 1));

  final dateFmt = DateFormat('dd-MM-yyyy');
  final timeFmt = DateFormat('HH:mm');

  final selection = await showDialog<_ReportSelection>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pickStartDate() async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: customStart,
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setDialogState(() {
              customStart = DateTime(
                picked.year,
                picked.month,
                picked.day,
                customStart.hour,
                customStart.minute,
              );
            });
          }
        }

        Future<void> pickStartTime() async {
          final picked = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(customStart),
          );
          if (picked != null) {
            setDialogState(() {
              customStart = DateTime(
                customStart.year,
                customStart.month,
                customStart.day,
                picked.hour,
                picked.minute,
              );
            });
          }
        }

        Future<void> pickEndDate() async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: customEnd,
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setDialogState(() {
              customEnd = DateTime(
                picked.year,
                picked.month,
                picked.day,
                customEnd.hour,
                customEnd.minute,
              );
            });
          }
        }

        Future<void> pickEndTime() async {
          final picked = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(customEnd),
          );
          if (picked != null) {
            setDialogState(() {
              customEnd = DateTime(
                customEnd.year,
                customEnd.month,
                customEnd.day,
                picked.hour,
                picked.minute,
              );
            });
          }
        }

        return AlertDialog(
          title: const Text('Storico / Select Period'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<_ReportKind>(
                  initialValue: reportKind,
                  decoration: const InputDecoration(
                    labelText: 'Tipo Report',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const <DropdownMenuItem<_ReportKind>>[
                    DropdownMenuItem(
                      value: _ReportKind.trips,
                      child: Text('Viaggi / Trips'),
                    ),
                    DropdownMenuItem(
                      value: _ReportKind.stops,
                      child: Text('Fermate / Stops'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => reportKind = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                RadioGroup<_PeriodOption>(
                  groupValue: period,
                  onChanged: (v) {
                    if (v != null) setDialogState(() => period = v);
                  },
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      RadioListTile<_PeriodOption>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Oggi (Today)'),
                        value: _PeriodOption.today,
                      ),
                      RadioListTile<_PeriodOption>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Ieri (Yesterday)'),
                        value: _PeriodOption.yesterday,
                      ),
                      RadioListTile<_PeriodOption>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Personalizzato (Custom)'),
                        value: _PeriodOption.custom,
                      ),
                    ],
                  ),
                ),
                if (period == _PeriodOption.custom) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text(
                    'Da:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickStartDate,
                          child: Text(dateFmt.format(customStart)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickStartTime,
                          child: Text(timeFmt.format(customStart)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickEndDate,
                          child: Text(dateFmt.format(customEnd)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickEndTime,
                          child: Text(timeFmt.format(customEnd)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AA5),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                DateTime startDt;
                DateTime endDt;
                final current = DateTime.now();
                final startOfToday =
                    DateTime(current.year, current.month, current.day);
                if (period == _PeriodOption.today) {
                  startDt = startOfToday;
                  endDt = startOfToday.add(const Duration(days: 1));
                } else if (period == _PeriodOption.yesterday) {
                  startDt = startOfToday.subtract(const Duration(days: 1));
                  endDt = startOfToday;
                } else {
                  startDt = customStart;
                  endDt = customEnd.isAfter(customStart)
                      ? customEnd
                      : customStart.add(const Duration(hours: 1));
                }

                Navigator.of(ctx).pop(
                  _ReportSelection(
                    kind: reportKind,
                    startIso: formatIsoUtc(startDt),
                    endIso: formatIsoUtc(endDt),
                  ),
                );
              },
              child: const Text('Mostra'),
            ),
          ],
        );
      },
    ),
  );

  if (selection == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => selection.kind == _ReportKind.trips
          ? TripsReportScreen(
              deviceId: deviceId,
              deviceName: deviceName,
              startIso: selection.startIso,
              endIso: selection.endIso,
            )
          : StopsReportScreen(
              deviceId: deviceId,
              deviceName: deviceName,
              startIso: selection.startIso,
              endIso: selection.endIso,
            ),
    ),
  );
}
