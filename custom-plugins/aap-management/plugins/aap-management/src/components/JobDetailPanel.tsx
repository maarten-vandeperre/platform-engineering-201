import React from 'react';
import {
  Box,
  Chip,
  CircularProgress,
  Collapse,
  Dialog,
  DialogContent,
  DialogTitle,
  IconButton,
  LinearProgress,
  Paper,
  Tab,
  Tabs,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
} from '@material-ui/core';
import CloseIcon from '@material-ui/icons/Close';
import ExpandLessIcon from '@material-ui/icons/ExpandLess';
import ExpandMoreIcon from '@material-ui/icons/ExpandMore';
import { Alert } from '@material-ui/lab';
import { useAapManagementApi } from '../plugin';
import {
  AapJob,
  AapJobEvent,
  AapJobRef,
  AapJobStdout,
  AapJobTaskLog,
  AapPagedResponse,
} from '../types';

type JobDetailPanelProps = {
  jobRef: AapJobRef | null;
  open: boolean;
  onClose: () => void;
};

const RUNNING_STATUSES = new Set(['running', 'pending', 'waiting', 'new']);

function statusColor(status: string, failed: boolean) {
  if (failed || status === 'failed' || status === 'error') {
    return 'secondary';
  }
  if (status === 'successful') {
    return 'primary';
  }
  return 'default';
}

function taskLogStatusColor(status: string) {
  if (status === 'failed' || status === 'unreachable') {
    return 'secondary';
  }
  if (status === 'ok') {
    return 'primary';
  }
  if (status === 'skipped') {
    return 'default';
  }
  return 'default';
}

function formatWhen(value?: string | null) {
  if (!value) {
    return '—';
  }
  return new Date(value).toLocaleString();
}

function isRunning(status?: string) {
  return Boolean(status && RUNNING_STATUSES.has(status));
}

function EventRow({ event }: { event: AapJobEvent }) {
  const [expanded, setExpanded] = React.useState(false);
  const hasStdout = Boolean(event.stdout?.trim());

  return (
    <>
      <TableRow
        hover={hasStdout}
        style={hasStdout ? { cursor: 'pointer' } : undefined}
        onClick={hasStdout ? () => setExpanded(value => !value) : undefined}
      >
        <TableCell>{event.counter ?? '—'}</TableCell>
        <TableCell>{event.event ?? '—'}</TableCell>
        <TableCell>{event.task ?? event.play ?? '—'}</TableCell>
        <TableCell>{event.hostName ?? '—'}</TableCell>
        <TableCell>{formatWhen(event.created)}</TableCell>
        <TableCell padding="checkbox">
          {hasStdout && (
            <IconButton
              size="small"
              aria-label={expanded ? 'collapse event output' : 'expand event output'}
              onClick={e => {
                e.stopPropagation();
                setExpanded(value => !value);
              }}
            >
              {expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
            </IconButton>
          )}
        </TableCell>
      </TableRow>
      {hasStdout && (
        <TableRow>
          <TableCell colSpan={6} style={{ paddingBottom: 0, paddingTop: 0, borderBottom: 0 }}>
            <Collapse in={expanded} timeout="auto" unmountOnExit>
              <Box
                p={2}
                mb={1}
                style={{
                  backgroundColor: '#1e1e1e',
                  color: '#f5f5f5',
                  borderRadius: 4,
                  maxHeight: 240,
                  overflow: 'auto',
                }}
              >
                <Typography
                  component="pre"
                  variant="body2"
                  style={{
                    margin: 0,
                    fontFamily: 'Menlo, Monaco, Consolas, monospace',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                  }}
                >
                  {event.stdout}
                </Typography>
              </Box>
            </Collapse>
          </TableCell>
        </TableRow>
      )}
    </>
  );
}

function TaskLogRow({ log }: { log: AapJobTaskLog }) {
  const [expanded, setExpanded] = React.useState(false);
  const hasStdout = Boolean(log.stdout?.trim());

  return (
    <>
      <TableRow
        hover={hasStdout}
        style={hasStdout ? { cursor: 'pointer' } : undefined}
        onClick={hasStdout ? () => setExpanded(value => !value) : undefined}
      >
        <TableCell>{log.counter ?? '—'}</TableCell>
        {log.workflowNode && <TableCell>{log.workflowNode}</TableCell>}
        <TableCell>{log.task || log.play || '—'}</TableCell>
        <TableCell>{log.host || '—'}</TableCell>
        <TableCell>
          <Chip
            size="small"
            label={log.status}
            color={taskLogStatusColor(log.status) as any}
          />
        </TableCell>
        <TableCell>{formatWhen(log.created)}</TableCell>
        <TableCell padding="checkbox">
          {hasStdout && (
            <IconButton
              size="small"
              aria-label={expanded ? 'collapse task log' : 'expand task log'}
              onClick={e => {
                e.stopPropagation();
                setExpanded(value => !value);
              }}
            >
              {expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
            </IconButton>
          )}
        </TableCell>
      </TableRow>
      {hasStdout && (
        <TableRow>
          <TableCell
            colSpan={log.workflowNode ? 7 : 6}
            style={{ paddingBottom: 0, paddingTop: 0, borderBottom: 0 }}
          >
            <Collapse in={expanded} timeout="auto" unmountOnExit>
              <Box
                p={2}
                mb={1}
                style={{
                  backgroundColor: '#1e1e1e',
                  color: '#f5f5f5',
                  borderRadius: 4,
                  maxHeight: 240,
                  overflow: 'auto',
                }}
              >
                <Typography
                  component="pre"
                  variant="body2"
                  style={{
                    margin: 0,
                    fontFamily: 'Menlo, Monaco, Consolas, monospace',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                  }}
                >
                  {log.stdout}
                </Typography>
              </Box>
            </Collapse>
          </TableCell>
        </TableRow>
      )}
    </>
  );
}

export function JobDetailPanel({ jobRef, open, onClose }: JobDetailPanelProps) {
  const api = useAapManagementApi();
  const [tab, setTab] = React.useState(0);
  const [loading, setLoading] = React.useState(false);
  const [taskLogsLoading, setTaskLogsLoading] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const [taskLogsError, setTaskLogsError] = React.useState<string>();
  const [job, setJob] = React.useState<AapJob>();
  const [stdout, setStdout] = React.useState<AapJobStdout>();
  const [events, setEvents] = React.useState<AapPagedResponse<AapJobEvent>>();
  const [taskLogs, setTaskLogs] = React.useState<AapPagedResponse<AapJobTaskLog>>();

  const load = React.useCallback(async () => {
    if (!jobRef) {
      return;
    }

    setError(undefined);
    try {
      const [jobDetail, stdoutData, eventsData] = await Promise.all([
        api.getJob(jobRef.id, jobRef.jobType),
        api.getJobStdout(jobRef.id, jobRef.jobType),
        api.getJobEvents(jobRef.id, jobRef.jobType, { page: 1, pageSize: 100 }),
      ]);
      setJob(jobDetail);
      setStdout(stdoutData);
      setEvents(eventsData);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [api, jobRef]);

  const loadTaskLogs = React.useCallback(async () => {
    if (!jobRef) {
      return;
    }

    setTaskLogsLoading(true);
    setTaskLogsError(undefined);
    try {
      const data = await api.getJobTaskLogs(jobRef.id, jobRef.jobType);
      setTaskLogs(data);
    } catch (e) {
      setTaskLogsError(e instanceof Error ? e.message : String(e));
    } finally {
      setTaskLogsLoading(false);
    }
  }, [api, jobRef]);

  React.useEffect(() => {
    if (!open || !jobRef) {
      return;
    }
    setTab(0);
    setJob(undefined);
    setStdout(undefined);
    setEvents(undefined);
    setTaskLogs(undefined);
    setTaskLogsError(undefined);
    setLoading(true);
    load();
  }, [jobRef, load, open]);

  React.useEffect(() => {
    if (!open || !jobRef || tab !== 1) {
      return;
    }
    loadTaskLogs();
  }, [jobRef, loadTaskLogs, open, tab]);

  React.useEffect(() => {
    if (!open || !jobRef || !job || !isRunning(job.status)) {
      return;
    }

    const timer = window.setInterval(() => {
      load();
      if (tab === 1) {
        loadTaskLogs();
      }
    }, 5000);
    return () => window.clearInterval(timer);
  }, [job, jobRef, load, loadTaskLogs, open, tab]);

  const workflowProgress = React.useMemo(() => {
    const nodes = job?.workflowNodes ?? [];
    if (!nodes.length) {
      return undefined;
    }
    const completed = nodes.filter(node => {
      const status = node.summary_fields?.job?.status ?? '';
      return status === 'successful' || status === 'failed' || status === 'error';
    }).length;
    return Math.round((completed / nodes.length) * 100);
  }, [job?.workflowNodes]);

  const showWorkflowNode = jobRef?.jobType === 'workflow_job';

  if (!jobRef) {
    return null;
  }

  return (
    <Dialog fullWidth maxWidth="lg" open={open} onClose={onClose} scroll="paper">
      <DialogTitle>
        <Box display="flex" alignItems="center" justifyContent="space-between">
          <Box>
            <Typography variant="h6">
              {job?.name ?? `Job #${jobRef.id}`}
            </Typography>
            <Typography variant="caption" color="textSecondary">
              #{jobRef.id} · {jobRef.jobType === 'workflow_job' ? 'Workflow' : 'Job'}
            </Typography>
          </Box>
          <Box display="flex" alignItems="center" gridGap={8}>
            {job && (
              <Chip
                size="small"
                label={job.status}
                color={statusColor(job.status, job.failed) as any}
              />
            )}
            <IconButton aria-label="close job detail" onClick={onClose}>
              <CloseIcon />
            </IconButton>
          </Box>
        </Box>
      </DialogTitle>
      <DialogContent dividers>
        {loading && !job && (
          <Box p={3} display="flex" justifyContent="center">
            <CircularProgress />
          </Box>
        )}

        {error && (
          <Box mb={2}>
            <Alert severity="error">{error}</Alert>
          </Box>
        )}

        {job && (
          <>
            {isRunning(job.status) && <LinearProgress style={{ marginBottom: 16 }} />}
            {workflowProgress !== undefined && (
              <Box mb={2}>
                <Typography variant="body2" gutterBottom>
                  Workflow progress: {workflowProgress}%
                </Typography>
                <LinearProgress variant="determinate" value={workflowProgress} />
              </Box>
            )}

            <Box display="flex" flexWrap="wrap" gridGap={16} mb={2}>
              <Typography variant="body2">
                <strong>Started:</strong> {formatWhen(job.started)}
              </Typography>
              <Typography variant="body2">
                <strong>Finished:</strong> {formatWhen(job.finished)}
              </Typography>
              {job.elapsed !== undefined && (
                <Typography variant="body2">
                  <strong>Elapsed:</strong> {job.elapsed}s
                </Typography>
              )}
              {job.playbook && (
                <Typography variant="body2">
                  <strong>Playbook:</strong> {job.playbook}
                </Typography>
              )}
            </Box>

            <Tabs
              value={tab}
              onChange={(_, value) => setTab(value)}
              indicatorColor="primary"
              textColor="primary"
            >
              <Tab label="Events" />
              <Tab label="Task logs" />
              <Tab label="Output" />
            </Tabs>

            {tab === 0 && (
              <Paper style={{ marginTop: 16 }}>
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell>#</TableCell>
                      <TableCell>Event</TableCell>
                      <TableCell>Task / Node</TableCell>
                      <TableCell>Host</TableCell>
                      <TableCell>Time</TableCell>
                      <TableCell padding="checkbox" />
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {(events?.results ?? []).map(event => (
                      <EventRow key={event.id} event={event} />
                    ))}
                    {!events?.results?.length && (
                      <TableRow>
                        <TableCell colSpan={6}>
                          <Typography variant="body2" color="textSecondary">
                            {isRunning(job.status)
                              ? 'Waiting for job events…'
                              : 'No events recorded for this run.'}
                          </Typography>
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </Paper>
            )}

            {tab === 1 && (
              <Paper style={{ marginTop: 16 }}>
                {taskLogsLoading && (
                  <Box p={3} display="flex" justifyContent="center">
                    <CircularProgress size={28} />
                  </Box>
                )}
                {taskLogsError && (
                  <Box p={2}>
                    <Alert severity="error">{taskLogsError}</Alert>
                  </Box>
                )}
                {!taskLogsLoading && !taskLogsError && (
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>#</TableCell>
                        {showWorkflowNode && <TableCell>Workflow node</TableCell>}
                        <TableCell>Task</TableCell>
                        <TableCell>Host</TableCell>
                        <TableCell>Status</TableCell>
                        <TableCell>Time</TableCell>
                        <TableCell padding="checkbox" />
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {(taskLogs?.results ?? []).map(log => (
                        <TaskLogRow key={`${log.id}-${log.counter ?? 0}`} log={log} />
                      ))}
                      {!taskLogs?.results?.length && (
                        <TableRow>
                          <TableCell colSpan={showWorkflowNode ? 7 : 6}>
                            <Typography variant="body2" color="textSecondary">
                              {isRunning(job.status)
                                ? 'Waiting for Ansible task output…'
                                : 'No task logs recorded for this run.'}
                            </Typography>
                          </TableCell>
                        </TableRow>
                      )}
                    </TableBody>
                  </Table>
                )}
              </Paper>
            )}

            {tab === 2 && (
              <Paper
                style={{
                  marginTop: 16,
                  padding: 16,
                  backgroundColor: '#1e1e1e',
                  color: '#f5f5f5',
                  maxHeight: 480,
                  overflow: 'auto',
                }}
              >
                {stdout?.note && (
                  <Typography variant="body2" style={{ marginBottom: 12, color: '#ccc' }}>
                    {stdout.note}
                  </Typography>
                )}
                <Typography
                  component="pre"
                  variant="body2"
                  style={{
                    margin: 0,
                    fontFamily: 'Menlo, Monaco, Consolas, monospace',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                  }}
                >
                  {stdout?.content?.trim()
                    ? stdout.content
                    : isRunning(job.status)
                      ? 'Job output will appear here as the run progresses…'
                      : 'No stdout captured for this run.'}
                </Typography>
              </Paper>
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
