import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('data page skeleton exposes one useful loading announcement', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: DataPageSkeleton(sectionLabel: 'inventory'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Loading inventory'), findsOneWidget);
    expect(find.byType(LoadingSkeletonBox), findsWidgets);
  });

  testWidgets('compact list skeleton renders the requested row count', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 600,
          child: DataListSkeleton(
            sectionLabel: 'customer statement',
            itemCount: 3,
          ),
        ),
      ),
    );

    expect(find.byType(Card), findsNWidgets(3));
    expect(find.bySemanticsLabel('Loading customer statement'), findsOneWidget);
  });
}
