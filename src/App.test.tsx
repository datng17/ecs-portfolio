import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import App from './App';

const SECTIONS = [
  { id: 'expertise', nav: 'Expertise', heading: 'Expertise' },
  { id: 'history', nav: 'History', heading: 'Career History' },
  { id: 'projects', nav: 'Projects', heading: 'Personal Projects' },
  { id: 'contact', nav: 'Contact', heading: 'Contact Me' },
];

describe('App', () => {
  test('renders the owner name and role', () => {
    render(<App />);
    expect(screen.getByRole('heading', { level: 1, name: 'Dat Nguyen' })).toBeInTheDocument();
    expect(screen.getByText('DevOps')).toBeInTheDocument();
  });

  test.each(SECTIONS)('renders the $heading section heading', ({ heading }) => {
    render(<App />);
    expect(screen.getByRole('heading', { level: 1, name: heading })).toBeInTheDocument();
  });

  test.each(SECTIONS)('$nav nav button scrolls to #$id', ({ id, nav }) => {
    // Navigation.scrollToSection has debug console.log calls; keep the CI output readable.
    const log = jest.spyOn(console, 'log').mockImplementation(() => {});
    render(<App />);
    const scrollIntoView = Element.prototype.scrollIntoView as jest.Mock;
    scrollIntoView.mockClear();

    // The closed mobile drawer is aria-hidden, so this matches only the desktop nav bar button.
    fireEvent.click(screen.getByRole('button', { name: nav }));

    expect(scrollIntoView).toHaveBeenCalledTimes(1);
    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: 'smooth' });
    expect(scrollIntoView.mock.instances[0]).toHaveAttribute('id', id);
    log.mockRestore();
  });

  test('theme toggle switches between dark and light mode', () => {
    const { container } = render(<App />);
    // The theme class sits on the root div, which has no accessible role to query by.
    // eslint-disable-next-line testing-library/no-node-access
    const root = container.firstChild as HTMLElement;

    expect(root).toHaveClass('main-container', 'dark-mode');
    expect(screen.queryByTestId('DarkModeIcon')).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId('LightModeIcon'));
    expect(root).toHaveClass('light-mode');
    expect(root).not.toHaveClass('dark-mode');
    expect(screen.queryByTestId('LightModeIcon')).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId('DarkModeIcon'));
    expect(root).toHaveClass('dark-mode');
    expect(root).not.toHaveClass('light-mode');
  });
});
