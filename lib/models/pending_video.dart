import 'package:hive/hive.dart';

class PendingVideo {
  final String id;
  final String localFilePath;
  final int timestamp;
  String status; // 'pending', 'uploading', 'complete', 'failed'
  Map<String, dynamic>? resultData;

  PendingVideo({
    required this.id,
    required this.localFilePath,
    required this.timestamp,
    this.status = 'pending',
    this.resultData,
  });
}

class PendingVideoAdapter extends TypeAdapter<PendingVideo> {
  @override
  final int typeId = 42; // Unique ID for this adapter

  @override
  PendingVideo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingVideo(
      id: fields[0] as String,
      localFilePath: fields[1] as String,
      timestamp: fields[2] as int,
      status: fields[3] as String,
      resultData: (fields[4] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, PendingVideo obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.localFilePath)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.resultData);
  }
}
