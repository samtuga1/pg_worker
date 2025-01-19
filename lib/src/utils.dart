import 'dart:mirrors';

extension PrimitiveType on Type {
  static final _primitiveTypes = {
    String: true,
    int: true,
    double: true,
    bool: true,
    num: true,
  };

  bool get isPrimitive => _primitiveTypes.containsKey(this);
}

extension ToJson on Object {
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = {};
    InstanceMirror instanceMirror = reflect(this);
    var classMirror = instanceMirror.type;

    classMirror.declarations.forEach((key, declaration) {
      if (declaration is VariableMirror && !declaration.isStatic) {
        String fieldName = MirrorSystem.getName(key);

        var fieldValue = instanceMirror.getField(key).reflectee;

        map[fieldName] = fieldValue;
      }
    });

    return map;
  }
}
