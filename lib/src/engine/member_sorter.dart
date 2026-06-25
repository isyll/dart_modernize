/// Reorders top-level declarations and the members inside each class, enum,
/// mixin, and extension into a canonical order: fields, then constructors, then
/// getters/setters, then methods. Within a group, members are sorted by name
/// (public before private), except fields, which keep their declared order so
/// field initialization order never changes.
///
/// Members only swap places and keep their original blank-line gaps, so the
/// rewritten file is the same length and the final `dart format` pass tidies up
/// the spacing. Import directives are left to the import organizer.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import 'edit_diff.dart';
import 'node_range.dart';
import 'source_edit.dart';

/// Returns the edits that sort the members of [unit], or an empty list when the
/// file is already sorted or cannot be sorted safely.
List<SourceEdit> sortMemberEdits(
  String content,
  CompilationUnit unit,
  LineInfo lineInfo,
) {
  final newCode = _MemberSorter(content, unit, lineInfo).run();
  if (newCode == null) return const [];
  final edit = computeSimpleDiff(content, newCode);
  return edit == null ? const [] : [edit];
}

class _MemberInfo {
  final _PriorityItem item;
  final String name;
  final int offset;
  final int end;
  final String text;

  _MemberInfo(this.item, this.name, this.offset, this.end, this.text);
}

enum _MemberKind {
  classAccessor,
  classConstructor,
  classField,
  classMethod,
  unitAccessor,
  unitClass,
  unitExtension,
  unitExtensionType,
  unitFunction,
  unitFunctionMain,
  unitFunctionType,
  unitGenericTypeAlias,
  unitVariable,
  unitVariableConst,
}

class _MemberSorter {
  static final List<_PriorityItem> _priorities = [
    _PriorityItem(false, _MemberKind.unitFunctionMain, false),
    _PriorityItem(false, _MemberKind.unitVariableConst, false),
    _PriorityItem(false, _MemberKind.unitVariableConst, true),
    _PriorityItem(false, _MemberKind.unitVariable, false),
    _PriorityItem(false, _MemberKind.unitVariable, true),
    _PriorityItem(false, _MemberKind.unitAccessor, false),
    _PriorityItem(false, _MemberKind.unitAccessor, true),
    _PriorityItem(false, _MemberKind.unitFunction, false),
    _PriorityItem(false, _MemberKind.unitFunction, true),
    _PriorityItem(false, _MemberKind.unitGenericTypeAlias, false),
    _PriorityItem(false, _MemberKind.unitGenericTypeAlias, true),
    _PriorityItem(false, _MemberKind.unitFunctionType, false),
    _PriorityItem(false, _MemberKind.unitFunctionType, true),
    _PriorityItem(false, _MemberKind.unitClass, false),
    _PriorityItem(false, _MemberKind.unitClass, true),
    _PriorityItem(false, _MemberKind.unitExtensionType, false),
    _PriorityItem(false, _MemberKind.unitExtensionType, true),
    _PriorityItem(false, _MemberKind.unitExtension, false),
    _PriorityItem(false, _MemberKind.unitExtension, true),
    _PriorityItem(true, _MemberKind.classField, false),
    _PriorityItem(true, _MemberKind.classAccessor, false),
    _PriorityItem(true, _MemberKind.classAccessor, true),
    _PriorityItem(false, _MemberKind.classField, false),
    _PriorityItem(false, _MemberKind.classConstructor, false),
    _PriorityItem(false, _MemberKind.classConstructor, true),
    _PriorityItem(false, _MemberKind.classAccessor, false),
    _PriorityItem(false, _MemberKind.classAccessor, true),
    _PriorityItem(false, _MemberKind.classMethod, false),
    _PriorityItem(false, _MemberKind.classMethod, true),
    _PriorityItem(true, _MemberKind.classMethod, false),
    _PriorityItem(true, _MemberKind.classMethod, true),
  ];
  final String _initialCode;
  final CompilationUnit _unit;

  final LineInfo _lineInfo;

  String code;

  _MemberSorter(this._initialCode, this._unit, this._lineInfo)
    : code = _initialCode;

  /// Sorts class members then unit members, returning the rewritten source or
  /// null when nothing changed.
  String? run() {
    _sortClassesMembers();
    _sortUnitMembers();
    return code == _initialCode ? null : code;
  }

  _MemberInfo _memberInfo(_PriorityItem item, String name, AstNode member) {
    final nodeRange = nodeWithComments(_lineInfo, member);
    final text = code.substring(nodeRange.offset, nodeRange.end);
    return _MemberInfo(item, name, nodeRange.offset, nodeRange.end, text);
  }

  void _sortAndReorderMembers(List<_MemberInfo> members) {
    final sorted = _sortedMembers(members);
    for (var i = members.length - 1; i >= 0; i--) {
      final newInfo = sorted[i];
      final oldInfo = members[i];
      if (!identical(newInfo, oldInfo)) {
        code =
            code.substring(0, oldInfo.offset) +
            newInfo.text +
            code.substring(oldInfo.end);
      }
    }
  }

  void _sortClassesMembers() {
    for (final member in _unit.declarations) {
      if (member is ClassDeclaration) {
        _sortClassMembers(member.body.members);
      } else if (member is EnumDeclaration) {
        _sortClassMembers(member.body.members);
      } else if (member is ExtensionDeclaration) {
        _sortClassMembers(member.body.members);
      } else if (member is ExtensionTypeDeclaration) {
        _sortClassMembers(member.body.members);
      } else if (member is MixinDeclaration) {
        _sortClassMembers(member.body.members);
      }
    }
  }

  void _sortClassMembers(List<ClassMember> membersToSort) {
    final members = <_MemberInfo>[];
    for (final member in membersToSort) {
      _MemberKind kind;
      var isStatic = false;
      String name;
      if (member is ConstructorDeclaration) {
        kind = _MemberKind.classConstructor;
        name = member.name?.lexeme ?? '';
      } else if (member is FieldDeclaration) {
        final fields = member.fields.variables;
        if (fields.isEmpty) return;
        kind = _MemberKind.classField;
        isStatic = member.isStatic;
        name = fields.first.name.lexeme;
      } else if (member is MethodDeclaration) {
        isStatic = member.isStatic;
        name = member.name.lexeme;
        if (member.isGetter) {
          kind = _MemberKind.classAccessor;
          name += ' getter';
        } else if (member.isSetter) {
          kind = _MemberKind.classAccessor;
          name += ' setter';
        } else {
          kind = _MemberKind.classMethod;
        }
      } else {
        // Unrecognized member kind; leave this class alone rather than risk a
        // bad reorder.
        return;
      }
      members.add(
        _memberInfo(_PriorityItem.forName(isStatic, name, kind), name, member),
      );
    }
    _sortAndReorderMembers(members);
  }

  List<_MemberInfo> _sortedMembers(List<_MemberInfo> members) {
    final result = List.of(members);
    result.sort((o1, o2) {
      final priority1 = _priorityOf(o1.item);
      final priority2 = _priorityOf(o2.item);
      if (priority1 != priority2) return priority1 - priority2;
      // Never reorder class fields: initialization order must be preserved.
      if (o1.item.kind == _MemberKind.classField) {
        return o1.offset - o2.offset;
      }
      var result = o1.name.toLowerCase().compareTo(o2.name.toLowerCase());
      if (result == 0) result = o1.name.compareTo(o2.name);
      if (result == 0) result = o1.offset - o2.offset;
      return result;
    });
    return result;
  }

  void _sortUnitMembers() {
    final members = <_MemberInfo>[];
    for (final member in _unit.declarations) {
      _MemberKind kind;
      String name;
      if (member is ClassDeclaration) {
        kind = _MemberKind.unitClass;
        name = member.namePart.typeName.lexeme;
      } else if (member is ClassTypeAlias) {
        kind = _MemberKind.unitClass;
        name = member.name.lexeme;
      } else if (member is EnumDeclaration) {
        kind = _MemberKind.unitClass;
        name = member.namePart.typeName.lexeme;
      } else if (member is ExtensionTypeDeclaration) {
        kind = _MemberKind.unitExtensionType;
        name = member.namePart.typeName.lexeme;
      } else if (member is ExtensionDeclaration) {
        kind = _MemberKind.unitExtension;
        name = member.name?.lexeme ?? '';
      } else if (member is FunctionDeclaration) {
        name = member.name.lexeme;
        if (member.isGetter) {
          kind = _MemberKind.unitAccessor;
          name += ' getter';
        } else if (member.isSetter) {
          kind = _MemberKind.unitAccessor;
          name += ' setter';
        } else {
          kind = name == 'main'
              ? _MemberKind.unitFunctionMain
              : _MemberKind.unitFunction;
        }
      } else if (member is FunctionTypeAlias) {
        kind = _MemberKind.unitFunctionType;
        name = member.name.lexeme;
      } else if (member is GenericTypeAlias) {
        kind = _MemberKind.unitGenericTypeAlias;
        name = member.name.lexeme;
      } else if (member is MixinDeclaration) {
        kind = _MemberKind.unitClass;
        name = member.name.lexeme;
      } else if (member is TopLevelVariableDeclaration) {
        final variables = member.variables.variables;
        if (variables.isEmpty) return;
        kind = member.variables.isConst
            ? _MemberKind.unitVariableConst
            : _MemberKind.unitVariable;
        name = variables.first.name.lexeme;
      } else {
        return;
      }
      members.add(
        _memberInfo(_PriorityItem.forName(false, name, kind), name, member),
      );
    }
    _sortAndReorderMembers(members);
  }

  static int _priorityOf(_PriorityItem item) {
    final index = _priorities.indexOf(item);
    return index != -1 ? index : 0;
  }
}

class _PriorityItem {
  final _MemberKind kind;
  final bool isPrivate;
  final bool isStatic;

  _PriorityItem(this.isStatic, this.kind, this.isPrivate);

  factory _PriorityItem.forName(bool isStatic, String name, _MemberKind kind) =>
      _PriorityItem(isStatic, kind, name.startsWith('_'));

  @override
  int get hashCode => Object.hash(kind, isPrivate, isStatic);

  @override
  bool operator ==(Object other) {
    if (other is! _PriorityItem) return false;
    // Class fields share one priority slot regardless of privacy so that
    // public and private fields keep their declared order.
    if (kind == _MemberKind.classField) {
      return other.kind == kind && other.isStatic == isStatic;
    }
    return other.kind == kind &&
        other.isPrivate == isPrivate &&
        other.isStatic == isStatic;
  }
}
