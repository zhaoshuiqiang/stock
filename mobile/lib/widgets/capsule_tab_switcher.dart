import 'package:flutter/material.dart';

class CapsuleTabSwitcher extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onTabChanged;

  const CapsuleTabSwitcher({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = index == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF58A6FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF8B949E),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
