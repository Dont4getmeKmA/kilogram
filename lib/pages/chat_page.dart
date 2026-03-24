import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kilogram/components/user_avatar.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/cubits/chat/chat_cubit.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/models/profile.dart';
import 'package:kilogram/models/message.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:timeago/timeago.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.otherUser});

  final Profile otherUser;

  static Route<void> route(String roomId, Profile otherUser) {
    return MaterialPageRoute(
      builder: (context) => BlocProvider<ChatCubit>(
        create: (context) {
          final cubit = ChatCubit();
          cubit.setMessagesListener(roomId);
          _fetchAndSetKeys(cubit, otherUser.id);
          return cubit;
        },
        child: ChatPage(otherUser: otherUser),
      ),
    );
  }

  static Future<void> _fetchAndSetKeys(
      ChatCubit cubit, String otherUserId) async {
    try {
      final data = await supabase
          .from('profiles')
          .select('rsa_public_key, elgamal_public_key, ecdh_public_key')
          .eq('id', otherUserId)
          .single();

      if (data['ecdh_public_key'] != null && !cubit.isClosed) {
        final keys = RemotePublicKeys(
          rsaPublicKey: data['rsa_public_key'] as String,
          elgamalPublicKey: data['elgamal_public_key'] as String,
          ecdhPublicKey: data['ecdh_public_key'] as String,
        );
        await cubit.setRecipientKeys(keys);
      }
    } catch (e) {
      debugPrint('Error fetching keys: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 1,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: otherUser.avatarUrl != null
                  ? NetworkImage(otherUser.avatarUrl!)
                  : null,
              child: otherUser.avatarUrl == null
                  ? Text(otherUser.username.substring(0, 2).toUpperCase(),
                      style: const TextStyle(fontSize: 14))
                  : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherUser.username,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Online',
                  style: TextStyle(fontSize: 12, color: Colors.green[400]),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            color: Theme.of(context).primaryColor,
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            color: Theme.of(context).primaryColor,
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.info),
            color: Theme.of(context).primaryColor,
            onPressed: () {},
          ),
        ],
      ),
      body: BlocConsumer<ChatCubit, ChatState>(
        listener: (context, state) {
          if (state is ChatError) {
            context.showErrorSnackBar(message: state.message);
          }
        },
        builder: (context, state) {
          if (state is ChatInitial) {
            return preloader;
          } else if (state is ChatLoaded) {
            final messages = state.messages;
            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _ChatBubble(message: message);
                    },
                  ),
                ),
                const _MessageBar(),
              ],
            );
          } else if (state is ChatEmpty) {
            return const Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'Start your conversation now :)',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                _MessageBar(),
              ],
            );
          } else if (state is ChatError) {
            return Center(child: Text(state.message));
          }
          throw UnimplementedError();
        },
      ),
    );
  }
}

class _MessageBar extends StatefulWidget {
  const _MessageBar();

  @override
  State<_MessageBar> createState() => _MessageBarState();
}

class _MessageBarState extends State<_MessageBar> {
  late final TextEditingController _textController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 8,
        left: 8,
        right: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.blueAccent),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _pickImage(ImageSource.camera),
          ),
          IconButton(
            icon: const Icon(Icons.photo, color: Colors.blueAccent),
            onPressed: () => _pickImage(ImageSource.gallery),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextFormField(
                keyboardType: TextInputType.multiline,
                maxLines: 5,
                minLines: 1,
                autofocus: true,
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blueAccent,
            radius: 20,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () => _submitMessage(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    _textController = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submitMessage() async {
    final text = _textController.text;
    if (text.isEmpty) {
      return;
    }
    BlocProvider.of<ChatCubit>(context).sendMessage(text);
    _textController.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);
    if (image == null) {
      return;
    }
    final imageBytes = await image.readAsBytes();
    if (mounted) {
      BlocProvider.of<ChatCubit>(context).sendImage(
        imageBytes: imageBytes,
        fileName: '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    }
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
  });

  final Message message;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfilesCubit, ProfilesState>(
      builder: (context, profileState) {
        final username = profileState is ProfilesLoaded
            ? (profileState.profiles[message.profileId]?.username ?? '')
            : '';

        List<Widget> chatContents = [
          if (!message.isMine)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UserAvatar(userId: message.profileId),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: message.isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      username,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: message.isMine
                            ? Colors.blueAccent.shade200
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                if (message.imageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.network(
                      message.imageUrl!,
                      fit: BoxFit.cover,
                      width: 200,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        );
                      },
                    ),
                  ),
                if (message.content.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color:
                          message.isMine ? Colors.blueAccent : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(message.isMine ? 18 : 4),
                        bottomRight: Radius.circular(message.isMine ? 4 : 18),
                      ),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: message.isMine ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
        if (message.isMine) {
          chatContents = chatContents.reversed.toList();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: message.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: message.isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: chatContents,
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  left: message.isMine ? 0 : 48,
                  right: message.isMine ? 8 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEncrypted)
                      const Padding(
                        padding: EdgeInsets.only(right: 3),
                        child: Icon(Icons.lock, size: 9, color: Colors.green),
                      ),
                    Text(
                      format(message.createdAt, locale: 'en_short'),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
