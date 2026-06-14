import React from 'react';
import {
  Box,
  Chip,
  CircularProgress,
  IconButton,
  LinearProgress,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TablePagination,
  TableRow,
  TextField,
  Tooltip,
  Typography,
} from '@material-ui/core';
import RefreshIcon from '@material-ui/icons/Refresh';
import { Alert } from '@material-ui/lab';
import { useDebouncedValue } from '../hooks';
import { useAapManagementApi } from '../plugin';
import { AapJob, AapPagedResponse } from '../types';

const PAGE_SIZE = 10;

function statusColor(status: string, failed: boolean) {
  if (failed || status === 'failed' || status === 'error') {
    return 'secondary';
  }
  if (status === 'successful') {
    return 'primary';
  }
  if (status === 'running' || status === 'pending' || status === 'waiting') {
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

export function JobHistoryTab() {
  const api = useAapManagementApi();
  const [page, setPage] = React.useState(0);
  const [search, setSearch] = React.useState('');
  const debouncedSearch = useDebouncedValue(search);
  const [initialLoading, setInitialLoading] = React.useState(true);
  const [refreshing, setRefreshing] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const [data, setData] = React.useState<AapPagedResponse<AapJob>>();

  const load = React.useCallback(async () => {
    setRefreshing(true);
    setError(undefined);
    try {
      const response = await api.listJobs({
        page: page + 1,
        pageSize: PAGE_SIZE,
        search: debouncedSearch.trim() || undefined,
      });
      setData(response);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setInitialLoading(false);
      setRefreshing(false);
    }
  }, [api, debouncedSearch, page]);

  React.useEffect(() => {
    load();
  }, [load]);

  return (
    <>
      <Box display="flex" alignItems="center" mb={2} gridGap={12}>
        <TextField
          label="Search runs"
          variant="outlined"
          size="small"
          value={search}
          onChange={event => {
            setPage(0);
            setSearch(event.target.value);
          }}
          style={{ minWidth: 260 }}
        />
        <Tooltip title="Refresh">
          <IconButton onClick={load} aria-label="refresh job history" disabled={refreshing}>
            <RefreshIcon />
          </IconButton>
        </Tooltip>
      </Box>

      {error && (
        <Box mb={2}>
          <Alert severity="error" title="Could not load job history">
            {error}
          </Alert>
        </Box>
      )}

      <Paper>
        {refreshing && <LinearProgress />}
        {initialLoading && !data ? (
          <Box p={4} display="flex" justifyContent="center">
            <CircularProgress />
          </Box>
        ) : (
          <>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Job</TableCell>
                  <TableCell>Template</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Started</TableCell>
                  <TableCell>Finished</TableCell>
                  <TableCell>Outcome</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {(data?.results ?? []).map(job => (
                  <TableRow key={job.id}>
                    <TableCell>
                      <Typography variant="body2">
                        <strong>{job.name}</strong>
                      </Typography>
                      <Typography variant="caption" color="textSecondary">
                        #{job.id}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      {job.summary_fields?.job_template?.name ??
                        job.summary_fields?.unified_job_template?.name ??
                        '—'}
                    </TableCell>
                    <TableCell>
                      <Chip
                        size="small"
                        label={job.status}
                        color={statusColor(job.status, job.failed) as any}
                      />
                    </TableCell>
                    <TableCell>{formatWhen(job.started)}</TableCell>
                    <TableCell>{formatWhen(job.finished)}</TableCell>
                    <TableCell>
                      {job.failed
                        ? 'Failed'
                        : job.status === 'successful'
                          ? 'Successful'
                          : job.status === 'running'
                            ? 'Running'
                            : job.status}
                    </TableCell>
                  </TableRow>
                ))}
                {!refreshing && (data?.results?.length ?? 0) === 0 && (
                  <TableRow>
                    <TableCell colSpan={6}>
                      <Typography variant="body2" color="textSecondary">
                        No job runs found.
                      </Typography>
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
            <TablePagination
              component="div"
              count={data?.count ?? 0}
              page={page}
              onPageChange={(_, nextPage) => setPage(nextPage)}
              rowsPerPage={PAGE_SIZE}
              rowsPerPageOptions={[PAGE_SIZE]}
            />
          </>
        )}
      </Paper>
    </>
  );
}
