import React from 'react';
import { Box, Chip } from '@material-ui/core';
import { Content, Header, Page } from '@backstage/core-components';
import { TemplatesTab } from './TemplatesTab';
import { JobHistoryTab } from './JobHistoryTab';
import { JobDetailPanel } from './JobDetailPanel';
import { AapJobRef } from '../types';

export function AapManagementPage() {
  const [tab, setTab] = React.useState(0);
  const [selectedJob, setSelectedJob] = React.useState<AapJobRef | null>(null);

  const openJob = React.useCallback((job: AapJobRef) => {
    setSelectedJob(job);
  }, []);

  const handleLaunched = React.useCallback((job: AapJobRef) => {
    setTab(1);
    setSelectedJob(job);
  }, []);

  return (
    <Page themeId="tool">
      <Header
        title="AAP Automation Templates"
        subtitle="Browse, search, and launch Ansible Automation Platform job templates"
      />
      <Content>
        <Box mb={2} display="flex" gridGap={8}>
          <Chip
            clickable
            color={tab === 0 ? 'primary' : 'default'}
            label="Templates"
            onClick={() => setTab(0)}
          />
          <Chip
            clickable
            color={tab === 1 ? 'primary' : 'default'}
            label="Run history"
            onClick={() => setTab(1)}
          />
        </Box>
        <Box hidden={tab !== 0}>
          <TemplatesTab onLaunched={handleLaunched} />
        </Box>
        <Box hidden={tab !== 1}>
          <JobHistoryTab onSelectJob={openJob} />
        </Box>
        <JobDetailPanel
          jobRef={selectedJob}
          open={Boolean(selectedJob)}
          onClose={() => setSelectedJob(null)}
        />
      </Content>
    </Page>
  );
}
