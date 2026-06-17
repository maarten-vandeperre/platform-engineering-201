import React from 'react';
import {
  Box,
  Chip,
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
import PlayArrowIcon from '@material-ui/icons/PlayArrow';
import RefreshIcon from '@material-ui/icons/Refresh';
import { Alert } from '@material-ui/lab';
import { LaunchTemplateDialog } from './LaunchTemplateDialog';
import { useDebouncedValue } from '../hooks';
import { useAapManagementApi } from '../plugin';
import { AapJobRef, AapJobTemplate, AapPagedResponse } from '../types';

const PAGE_SIZE = 10;

type TemplatesTabProps = {
  onLaunched: (job: AapJobRef) => void;
};

function templateTypeLabel(templateType: AapJobTemplate['templateType']) {
  return templateType === 'workflow_job_template' ? 'Workflow' : 'Job';
}

function labelChips(template: AapJobTemplate) {
  const labels = template.summary_fields?.labels?.results ?? [];
  if (!labels.length) {
    return '—';
  }
  return (
    <Box display="flex" flexWrap="wrap" gridGap={4}>
      {labels.map(label => (
        <Chip key={label.id} size="small" label={label.name} />
      ))}
    </Box>
  );
}

export function TemplatesTab({ onLaunched }: TemplatesTabProps) {
  const api = useAapManagementApi();
  const [page, setPage] = React.useState(0);
  const [search, setSearch] = React.useState('');
  const [labels, setLabels] = React.useState('');
  const debouncedSearch = useDebouncedValue(search);
  const debouncedLabels = useDebouncedValue(labels);
  const [initialLoading, setInitialLoading] = React.useState(true);
  const [refreshing, setRefreshing] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const [launchTarget, setLaunchTarget] = React.useState<AapJobTemplate | null>(null);
  const [data, setData] = React.useState<AapPagedResponse<AapJobTemplate>>();

  const load = React.useCallback(async () => {
    setRefreshing(true);
    setError(undefined);
    try {
      const response = await api.listJobTemplates({
        page: page + 1,
        pageSize: PAGE_SIZE,
        search: debouncedSearch.trim() || undefined,
        labels: debouncedLabels.trim() || undefined,
      });
      setData(response);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setInitialLoading(false);
      setRefreshing(false);
    }
  }, [api, debouncedLabels, debouncedSearch, page]);

  React.useEffect(() => {
    load();
  }, [load]);

  return (
    <>
      <Box display="flex" alignItems="center" mb={2} gridGap={12}>
        <TextField
          label="Search name or description"
          variant="outlined"
          size="small"
          value={search}
          onChange={event => {
            setPage(0);
            setSearch(event.target.value);
          }}
          style={{ minWidth: 260 }}
        />
        <TextField
          label="Filter labels"
          variant="outlined"
          size="small"
          value={labels}
          onChange={event => {
            setPage(0);
            setLabels(event.target.value);
          }}
          style={{ minWidth: 200 }}
        />
        <Tooltip title="Refresh">
          <IconButton onClick={load} aria-label="refresh templates" disabled={refreshing}>
            <RefreshIcon />
          </IconButton>
        </Tooltip>
      </Box>

      {error && (
        <Box mb={2}>
          <Alert severity="error" title="Could not load templates">
            {error}
          </Alert>
        </Box>
      )}

      <Paper>
        {refreshing && <LinearProgress />}
        {initialLoading && !data ? (
          <Box p={4} display="flex" justifyContent="center">
            <LinearProgress style={{ width: '40%' }} />
          </Box>
        ) : (
          <>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Name</TableCell>
                  <TableCell>Type</TableCell>
                  <TableCell>Organization</TableCell>
                  <TableCell>Project</TableCell>
                  <TableCell>Labels</TableCell>
                  <TableCell align="right">Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {(data?.results ?? []).map(template => (
                  <TableRow key={template.id}>
                    <TableCell>
                      <Typography variant="body2">
                        <strong>{template.name}</strong>
                      </Typography>
                      {template.description && (
                        <Typography variant="caption" color="textSecondary">
                          {template.description}
                        </Typography>
                      )}
                    </TableCell>
                    <TableCell>
                      <Chip
                        size="small"
                        label={templateTypeLabel(template.templateType)}
                      />
                    </TableCell>
                    <TableCell>
                      {template.summary_fields?.organization?.name ?? '—'}
                    </TableCell>
                    <TableCell>
                      {template.summary_fields?.project?.name ?? '—'}
                    </TableCell>
                    <TableCell>{labelChips(template)}</TableCell>
                    <TableCell align="right">
                      <Tooltip title="Launch template">
                        <span>
                          <IconButton
                            aria-label={`launch ${template.name}`}
                            disabled={refreshing}
                            onClick={() => setLaunchTarget(template)}
                          >
                            <PlayArrowIcon />
                          </IconButton>
                        </span>
                      </Tooltip>
                    </TableCell>
                  </TableRow>
                ))}
                {!refreshing && (data?.results?.length ?? 0) === 0 && (
                  <TableRow>
                    <TableCell colSpan={6}>
                      <Typography variant="body2" color="textSecondary">
                        No job templates match your filters.
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
      <LaunchTemplateDialog
        template={launchTarget}
        open={Boolean(launchTarget)}
        onClose={() => setLaunchTarget(null)}
        onLaunched={job => {
          load();
          onLaunched(job);
        }}
      />
    </>
  );
}
