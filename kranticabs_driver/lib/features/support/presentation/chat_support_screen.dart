import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/support_providers.dart';
import '../data/support_models.dart';

class ChatSupportScreen extends ConsumerStatefulWidget {
  final String? ticketCode;

  const ChatSupportScreen({super.key, this.ticketCode});

  @override
  ConsumerState<ChatSupportScreen> createState() => _ChatSupportScreenState();
}

class _ChatSupportScreenState extends ConsumerState<ChatSupportScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.ticketCode == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(ticketThreadProvider(widget.ticketCode!).notifier).reply(text);
      _messageController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ticketCode == null) {
      return _TicketListView();
    }
    return _buildThread(context);
  }

  Widget _buildThread(BuildContext context) {
    final threadState = ref.watch(ticketThreadProvider(widget.ticketCode!));
    final ticket = threadState.ticket;

    return Scaffold(
      appBar: CustomAppBar(title: ticket?.title.isNotEmpty == true ? ticket!.title : 'Support Ticket'),
      body: Column(
        children: [
          if (threadState.loading && ticket == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (ticket == null)
            const Expanded(
              child: EmptyState(icon: Icons.error_outline, title: 'Could not load ticket'),
            )
          else ...[
            _StatusBanner(status: ticket.status),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: ticket.messages.length,
                itemBuilder: (context, index) {
                  final message = ticket.messages[index];
                  final isDriver = message.senderRole == 'driver';
                  return Align(
                    alignment: isDriver ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isDriver ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isDriver ? null : Border.all(color: AppColors.lightBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.message,
                            style: TextStyle(
                              color: isDriver ? Colors.white : AppColors.lightTextPrimary,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message.senderName.isEmpty ? message.senderRole : message.senderName,
                            style: TextStyle(
                              color: isDriver ? Colors.white70 : AppColors.lightTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: AppColors.lightBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : _send,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketListView extends ConsumerWidget {
  const _TicketListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Support Tickets',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/raise-ticket'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myTicketsProvider.future),
        child: ticketsAsync.when(
          data: (tickets) {
            if (tickets.isEmpty) {
              return ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: EmptyState(
                      icon: Icons.confirmation_num_outlined,
                      title: 'No support tickets yet',
                      subtitle: 'Raise a ticket and our team will get back to you',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tickets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return _TicketTile(
                  ticket: ticket,
                  onTap: () => context.push('/chat-support', extra: ticket.ticketCode),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const EmptyState(icon: Icons.error_outline, title: 'Could not load tickets'),
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;

  const _TicketTile({required this.ticket, required this.onTap});

  Color _statusColor() {
    switch (ticket.status) {
      case 'closed':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.title.isEmpty ? 'General Support' : ticket.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#${ticket.ticketCode}',
                    style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ticket.status,
                style: TextStyle(color: _statusColor(), fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  Color _color() {
    switch (status) {
      case 'closed':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _color().withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Status: $status',
        style: TextStyle(color: _color(), fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
